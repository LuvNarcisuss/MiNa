# MiNa delivery record

## App and cloud

- App, scheme and target are named MiNa. The iPhone-only host uses React Native 0.88.1 and iOS 16.0 or newer. The local bundle identifier is com.mina.bedtime. Release signing and App Store products require owner-provided identifiers.
- The Gmail-linked organization hosts MiNa in Tokyo. Project reference is nojpfyqctfwdshqnzudp. The owner explicitly approved permanent removal of Toli. The dashboard acknowledged deletion, and the organization listing subsequently contained MiNa and Sese.
- Anonymous Supabase Auth is enabled. Sign-in uses the public app key, creates or restores a genuine user session and bootstraps an owned profile. Session credentials use Keychain. “Sign out” locks access in this installation and “Continue” reopens its device identity. Cross-device account recovery is pending.
- The deployed database covers profiles, visibility, follows, blocks, reports, posts, dreams, private media, comments, reactions, messages, calling, room presence, seats, audio signaling, gifts, wallet records and support. Each local migration filename matches its remote migration version. The app uses signed media URLs and user-scoped requests.
- Central plus opens AI Companion. The three illustrated topic cards work without a model. On compatible iPhones the conversation uses Apple's local Foundation Models framework. The service provides renewable, free 60-minute sessions and a ten-minute warning. No third-party inference key is embedded.
- Profile feedback submits to a protected support table. The owner requested that the public support email stay blank. The in-app agreement text and publicly readable PDFs use the support form as the contact channel. Public GET responses for both PDFs matched the checked-in documents byte for byte.
- Room audio and one-to-one calls use WebRTC and authenticated, participant-scoped signaling. A foreground receiver can answer or decline. Production TURN configuration, background incoming-call notifications and physical-device audio acceptance remain outstanding.
- Twenty gifts and VIP0 through VIP12 are available in the interface. Gift delivery, inventory, spending and check-in use server-side transactions. Coin packages remain unavailable while the App Store catalog and verified purchase delivery are unconfigured. The application does not charge to create rooms, request music or start the on-device companion.

## Current verification

The Release build succeeded for an iPhone 17 Pro simulator on iOS 26.0 using Xcode 26.0.1. The installed app reports UIDeviceFamily 1. The bundled RN host and local H5 archive were present. Native extraction completed on launch and all 511 extracted resources matched the SHA-256 manifest.

A database transaction exercised real authenticated-role and RPC behavior using two isolated identities. It verified host approval and queue removal, repeat-safe check-in, free-gift limits, repeat-safe inventory acquisition, paid gift and inventory debits, insufficient balance, ranking scores and wallet isolation. The test rolled back its rows. This was a database test and made no App Store purchase.

The acceptance record in the acceptance directory contains screenshots observed on the selected simulator. Apple sandbox and production payment, real acoustic capture and playback across two phones, carrier-network media traversal and on-device language-model output still require suitable devices and configuration.

## Simulator journeys and build output

The initial acceptance run exercised consent, anonymous sign-in, Rooms, the central AI Companion destination, all three topic dialogs, Dream Square and Profile. A second journey covered the Feed video composer, disabled empty submission, notification categories, unavailable coin packages, the 20-item store, local soundscape playback, pause and exit. Both XCTest journeys passed.

Visual review identified low contrast in the status bar above dark screens. The host now switches the iOS status bar appearance in response to the active screen. The simulator build after this correction is in build/Release-iphonesimulator/MiNa.app. Its embedded page bundle matches build/MiNaPages.zip. The verified package digest is 669794012d8997429886b88337e072dd0e99b70ba9ca56eff86d339a33535c54. The simulator app passed strict code-signature verification.

The final installed Release was exercised again with the signed-in simulator identity. Both UI journeys passed with zero failures in 94.420 seconds. The first consent screenshot is retained from the initial run. The other thirteen screenshots are from the final run and confirm legible light status text on night surfaces and dark text on light surfaces.

Two temporary online accounts exercised message creation and Realtime delivery, duplicate-send handling, unread and deletion scope, and call signaling through hang-up. Both were removed through the deployed account-deletion endpoint. An initial content-count assertion revealed an embedded aggregation issue. The entry_feed migration corrected it. A separate two-identity, rollback-only database check confirmed one like, one comment and correct per-reader saved and liked states after the correction. These observations cover signaling and database behavior, without establishing a two-device acoustic call.

After the migration, the complete online API check passed all 23 assertions. Two fresh authenticated accounts verified Realtime message delivery, call signaling and privacy controls, feed totals and per-reader reactions, signed audio downloads with identical bytes, ownership protection, and blocking for both feed visibility and messaging. The deployed account-deletion endpoint confirmed removal of both temporary accounts.
