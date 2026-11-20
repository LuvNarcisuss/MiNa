# MiNa

MiNa is an iPhone bedtime voice community. The central plus opens AI Companion. The app bundles its React and TypeScript interface and original artwork as a verified local ZIP and presents it through a React Native WebView.

## Open the app

Open `ios/MiNa.xcworkspace`, choose the **MiNa** scheme and an iPhone destination. The deployment target is iOS 16.0. Native dependencies are pinned by the npm and CocoaPods lockfiles. On a fresh checkout, use `npm ci`, then `pod install --project-directory=ios`. Xcode packages the web pages and the React Native bundle during a normal build. A standalone web archive can also be generated with `npm run package:web`.

## Project map

- `web/src` contains the application screens, authenticated Supabase client and bounded native bridge.
- `web/public/art` contains UI exports and three original soundscapes. See [artwork provenance](docs/Artwork.md).
- `ios/MiNa` implements archive verification, local media, protected sessions, on-device inference and policy viewing.
- `supabase/migrations` maintains database tables, access rules and atomic operations. `supabase/functions` contains the deployed policy and account-deletion endpoints.
- [Product design and source boards](docs/MiNa-Product-Design.md) describe the approved design. [Delivery record](docs/Delivery.md) records integration decisions and verification.

The project-specific signing team and App Store consumable identifiers are pending. This checkout uses com.mina.bedtime for local development.
