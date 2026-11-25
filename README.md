# MiNa

MiNa is an iPhone bedtime voice community built with SwiftUI. Rooms, Feed, AI Companion, Messages and Profile share a native navigation stack. The center button opens AI Companion.

## Open the app

Open `ios/MiNa.xcodeproj`, select the MiNa scheme and choose an iPhone running iOS 16.0 or later. Xcode resolves WebRTC 137.0.0 through Swift Package Manager for room audio and private calls. MiNa Companion uses the authenticated Supabase function `companion-chat`. Configure `GROQ_API_KEY` in Edge Function Secrets. The default Groq model is `openai/gpt-oss-20b`. Release signing and activation of the seven App Store products require the MiNa developer account. See [wallet configuration](docs/Wallet.md).

## Create a sign-in account

In the app, select **Create account**, enter your email and your password twice, and accept the terms. When the account creation alert appears, tap **OK** to return to sign-in. Your email stays filled in. Enter your password to sign in.

Administrators can also provision an account. Open the [company MiNa user list](https://supabase.com/dashboard/project/weieitgfketnpvvwvfpa/auth/users). Select **Add user** and **Create new user**. Enter the email and password and select **Auto Confirm User** for an account that should be ready to use immediately. The iPhone app connects to this company project. Enter the same credentials in MiNa and accept the terms. The first successful sign-in initializes the account profile and personal settings.

## Project map

- `ios/MiNa` contains Swift screens, audio and media handling, the authenticated service client and account storage.
- `ios/MiNa/Artwork` holds design sources for the cloud artwork release. The iPhone downloads interface artwork and soundscapes from Supabase Storage. See [artwork provenance](docs/Artwork.md).
- `supabase/migrations` defines database access and transactions. The Edge Functions in `supabase/functions` include policies, account deletion and live gift authorization. The iPhone verifies and credits StoreKit purchases locally.
- [Product design](docs/MiNa-Product-Design.md) describes the approved journeys and source boards. [Delivery record](docs/Delivery.md) distinguishes current checks from earlier acceptance runs.
