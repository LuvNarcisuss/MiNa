# MiNa wallet

The Profile wallet and the insufficient-balance actions open the same SwiftUI screen. Each purchase buys one consumable pack. The product artwork and existing gift economy use star coins. The catalog uses the quantities from the supplied purchase sheet.

| App Store product ID | Star coins | US price |
| --- | ---: | ---: |
| iukawygoozctrvri | 400 | $0.99 |
| iuksdwimsbrhwuza | 800 | $1.99 |
| kbuujljqmlnqmmpp | 2,450 | $4.99 |
| yyzthxzkykuwreyt | 5,150 | $9.99 |
| mxvqqvbrxagzhpzd | 10,800 | $19.99 |
| cbdqrfufpxoocyou | 29,400 | $49.99 |
| ezcsvqkqboqagspr | 63,700 | $99.99 |

## StoreKit 1 checkout

The signed-in account requests localized prices with `SKProductsRequest`. Checkout submits one unit through `SKPaymentQueue`, with the account UUID in `applicationUsername`. The purchase observer lives for the app session. Checkout, receipt verification, purchase history and credit delivery run independently of MiNa's services.

For a purchased transaction, TPInAppReceipt 4.0.2 verifies the signed app receipt on the iPhone. MiNa checks the receipt environment, bundle, product, transaction ID, quantity, cancellation, subscription fields and the account on the queued payment. A missing receipt or transaction triggers a StoreKit receipt refresh. Xcode receipts are accepted only in a Debug simulator build. Production, Apple sandbox and Xcode use separate ledgers.

One device-only Keychain item per account and environment holds purchase entries and spending reservations. A successful Keychain write commits the credit and its transaction ID together before the app finishes the StoreKit transaction. Repeated callbacks do not increase the balance or repeat the success alert. A failed verification or write leaves the payment unfinished. Next launch, foreground entry or wallet refresh retries eligible payments. Deferred and canceled payments grant no coins. The Xcode ledger reads the previous account-specific test history on first use. Local coins and locally purchased backpack items stay on this iPhone.

## Store and live gifts

Buying a priced store item entirely with local coins saves its debit and backpack quantity in one local write. The existing catalog supplies the price. Free claims, earlier server funds and server inventory keep their original rules. StoreKit test coins can buy items in the local test backpack. Live rooms use production funds and inventory.

For a live gift or a store purchase using both sources, the app reserves the device contribution under the operation UUID. Apple App Attest signs the account, operation, recipients, item, quantity, current quote and device contribution. Only the spending authorization goes to `gift-spend`. The database checks the catalog, original request, room status, participants and blocking, applies any server-funded remainder, and commits one receipt. Delivery contributes the normal gift value to rankings. A retry uses the same operation. When delivery is uncertain, the spending screens reconcile the reservation with a receipt or a server cancellation that prevents a late delivery. A confirmed cancellation releases the local reservation.

## Release dependencies

The checked-in `device_gift_spending` migration and `gift-spend` function support device-funded live delivery. The production function needs MiNa's `MINA_APPLE_TEAM_ID` and an iPhone build signed for `com.mina.bedtime` with the production App Attest entitlement. These dependencies apply to shared gift fulfillment. StoreKit purchase verification and local store purchases do not need an attestation key.

The replacement `wallet-purchase` handler returns an upgrade message to earlier clients. At cutover, retire the old verifier and freeze legacy credits before distributing the new client. Bundle the result of this read-only export as `ios/MiNa/LegacyPurchaseCredits.json`:

```sql
select coalesce(json_agg(encode(sha256(convert_to(environment || ':' || transaction_id, 'UTF8')), 'hex')), '[]'::json)
from public.coin_purchases;
```

The app finishes an already credited legacy transaction without issuing a second grant. The bundled snapshot contains only hashes and currently represents an empty purchase history. Keep historical wallet, purchase and inventory records. On November 25, 2026 a read-only count in the MiNa company project returned zero recorded purchases and zero positive server balances. This count describes that snapshot only.

## Verification

The shared scheme selects `Configuration/MiNaCoins.storekit` for its Debug Run. For Apple sandbox product lookup, select None for the StoreKit configuration. Release signing and App Store Connect product activation require the MiNa developer account.

The November 24 simulator check inspected the seven localized fixture prices and submitted no purchase. It predates the local-wallet change. This revision has undergone static inspection only. Local StoreKit delivery and redelivery, account switching, interrupted writes, App Attest on a signed iPhone, live gift settlement, Apple sandbox and production purchases still require runtime verification.
