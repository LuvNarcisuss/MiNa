# MiNa project rules

Build an iPhone-only bedtime voice community named MiNa. Follow docs/MiNa-Product-Design.md. The central plus opens AI Companion. Use Swift and SwiftUI for all product screens, with native audio and media integrations. Keep Swift sources in ios/MiNa and original-derived artwork in ios/MiNa/Artwork. Keep the supplied original boards and design archives intact. Use natural English throughout the app.

Show actions and their states through familiar controls. Omit captions that repeat what the controls already convey. Keep permission recovery on the affected control and provide descriptive accessibility labels.

Present errors in a native alert with actionable English wording on every screen and sheet. Keep retry controls accessible and technical diagnostics out of user-facing messages.

Keep service availability, profile ownership and payment states truthful. Use stable identifiers and durable writes for personal data. Preserve session compatibility and account-specific media directories. Release signing, service accounts and purchase identifiers require project-specific configuration.

Static inspection and project metadata generation are permitted. Compilation, type checking, launching and runtime tests require explicit user authorization.
