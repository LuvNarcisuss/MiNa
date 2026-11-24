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

## Checkout and delivery

The app requests all seven products through StoreKit 1. Only products returned with a localized price are selectable. Checkout confirms the authenticated wallet, server package quantity and receipt protocol before submitting one payment with the owner's UUID as its application username.

After a purchased callback, the app reads the App Store receipt. A retained StoreKit request refreshes a missing receipt, or a receipt that Apple verified but that lacks the requested transaction. Concurrent readers share the refresh, with cancellation on account change and a 30-second timeout. An unfinished payment remains available for retry after relaunch or a wallet refresh.

The authenticated Edge Function sends the receipt to Apple's production verification endpoint and retries against Apple's sandbox only for status 21007. It checks the response environment, receipt type, bundle, transaction, original transaction, product, unit quantity, purchase date and relevant ownership, cancellation and subscription fields before requesting credit. Xcode fixture transactions cannot fund either ledger.

Apple marks this receipt service deprecated. MiNa uses it for compatibility with its original StoreKit client. This consumable verification path requires no In-App Purchase signing key or subscription shared secret. [Apple receipt validation](https://developer.apple.com/documentation/storekit/validating-receipts-with-the-app-store)

The local queue checks the account UUID on the payment. The server checks Apple's account token whenever the matching receipt row includes it. With a tokenless legacy receipt, possession of the Apple-verified receipt permits the first authenticated claim. The database binds that claim to the account and rejects cross-account replay. A stolen tokenless receipt presented before the legitimate claim is a residual ownership risk. Receipts are transmitted over HTTPS and are never written to application logs or purchase history.

The service-only database function serializes credits with wallet spending. A production credit updates the spendable balance and records the purchase atomically. Verified sandbox credits use their own ledger. Below the seven packages, Purchase history lists the latest 50 confirmed purchases for the current account and environment, newest first. Each row shows the credit and time. View all opens recent activity including spending. Selecting a package opens native checkout. Each newly delivered purchase triggers a success alert. The environment and transaction ID stay unique after account deletion. After acknowledgement the app reads the corresponding authoritative balance, finishes the transaction and signals the activity view to reload. Repeated delivery acknowledgements do not trigger a second success alert. Failed or canceled payments grant nothing. Deferred purchases await approval.

## Deployment and verification

The MiNa Supabase project has migration `20261123083312_wallet_purchases` and active Edge Function `wallet-purchase` version 1. The deployed source matched the repository on readback. The remote catalog matched all seven configured quantities. Read-only checks confirmed purchase row security, an invoker-scoped sandbox balance view and service-only access to the credit operation. The function validates each caller's bearer token with Supabase Auth.

The shared MiNa scheme selects `Configuration/MiNaCoins.storekit` for Xcode Run. Open `ios/MiNa.xcodeproj`, select MiNa QA, and use Run to start the local StoreKit session. Launching an installed app directly does not configure that session. For the Apple catalog, select None under Edit Scheme → Run → Options → StoreKit Configuration. Archives use Release.

On a Debug simulator, TPInAppReceipt validates a purchased Xcode receipt against its test certificate. The app checks the bundle, account on the queued payment, transaction, product, quantity and cancellation before atomically recording the test credit in the account's local library. The local purchase page displays the local ledger with the same labels as the Apple-backed page. Apple-backed purchases continue through the remote verifier. The WalletCatalog diagnostic log records the product response count and invalid product IDs. App Store Connect product availability and release signing are separate from the deployed backend. On November 24, 2026, Xcode built and launched the shared scheme on MiNa QA (iPhone 17 Pro, iOS 26.3, UDID DBFA7AD1-FB00-4FB8-8287-D8E72FE9594E). A read-only XCTest opened the signed-in wallet and verified all seven price labels and enabled states against the US fixture. One case passed with zero failures. No purchase was submitted. Local credit delivery, Apple sandbox catalog and delivery, and production purchases remain unverified. [Wallet on MiNa QA](qa/2026-11-24/wallet-prices.png)
