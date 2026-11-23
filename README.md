# MiNa

MiNa is an iPhone bedtime voice community built with SwiftUI. Rooms, Feed, AI Companion, Messages and Profile share a native navigation stack. The center button opens AI Companion.

## Open the app

Open `ios/MiNa.xcodeproj`, select the MiNa scheme and choose an iPhone running iOS 16.0 or later. Xcode resolves WebRTC 137.0.0 through Swift Package Manager for room audio and private calls. On-device companion replies require a compatible device with Apple Intelligence. Release signing and App Store product identifiers require project-specific configuration.

## Project map

- `ios/MiNa` contains Swift screens, audio and media handling, the authenticated service client and account storage.
- `ios/MiNa/Artwork` contains original-derived interface artwork and three soundscapes. See [artwork provenance](docs/Artwork.md).
- `supabase/migrations` defines database access and transactions. The Edge Functions in `supabase/functions` serve policies and handle account deletion.
- [Product design](docs/MiNa-Product-Design.md) describes the approved journeys and source boards. [Delivery record](docs/Delivery.md) distinguishes current checks from earlier acceptance runs.
