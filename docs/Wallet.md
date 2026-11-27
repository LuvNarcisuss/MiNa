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

A successful StoreKit purchase adds the pack once to the signed-in account’s device balance. Sending a catalog gift uses its unit price times its quantity. Sending an item already in the backpack consumes the item. The same rules apply to the active Xcode, sandbox or production wallet, whose purchase balances remain separate.

When the sender is alone in a room that accepts gifts, the gift drawer opens the friend invitation list. A single other listener is preselected when they join. With several listeners, the sender can choose the recipient. If the selected listener leaves before sending, the drawer returns to gift selection and requires a new review.

The local ledger reserves the debit before the app submits a room delivery. Supabase checks the signed-in sender, active room participants, room settings, blocks and catalog price, then stores a single recipient-visible gift receipt. A retry uses the same operation ID. After a lost response the service serializes reconciliation against delivery, confirms the receipt or closes the operation and releases the local funds. A paid addition to the backpack funded entirely on the device is one local write.

Earlier server funds and backpack inventory remain usable. The database debits only the remaining server-funded share. Items bought with a device contribution stay in the device backpack. Only server-backed value is eligible for the shared spending ranking. A device-funded gift still records the selected item, quantity, sender and recipient.

## Deployment

The company project serves the authenticated `deliver_wallet_gift` and `resolve_device_gift` RPCs. Neither requires an Apple Team ID or a device attestation service. The previous `wallet-purchase` Edge Function was removed from the company dashboard. Its public route returned HTTP 404. The historical SQL function `credit_coin_purchase` still exists because the separate cleanup migration was declined. Current iOS purchases do not call it.

The app finishes an already credited legacy transaction without issuing a second grant. The bundled snapshot contains only hashes and currently represents an empty purchase history. Keep historical wallet, purchase and inventory records. On November 25, 2026 a read-only count in the MiNa company project returned zero recorded purchases and zero positive server balances. This count describes that snapshot only.

## Verification

The shared scheme selects `Configuration/MiNaCoins.storekit` for its Debug Run. For Apple sandbox product lookup, select None for the StoreKit configuration. Release signing and App Store Connect product activation require the MiNa developer account.

The November 24 simulator check inspected the seven fixture prices before the local-wallet change. On November 25, Xcode StoreKit Test exercised all seven purchases, local delivery and duplicate callbacks. The [November 25 regression review](qa/2026-11-25/Regression.md) records the balances and observed deployment state. A later test on the same simulator bought 400 coins using StoreKit Test and sent two gifts at 29 coins each. The recipient read one receipt and a retry kept the balance at 342. Adding a backpack item cost 29 coins. Sending that stored item incurred no second charge. An insufficient balance and a room with gifts disabled each left the persisted balance at 313. Both temporary accounts were removed. Account switching during checkout, interrupted writes and Apple sandbox or production purchases still require separate evidence.
