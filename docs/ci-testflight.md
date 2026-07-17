# iOS TestFlight CI

GitHub Actions builds Balm for iOS and uploads to TestFlight on every push to
`main` that touches the app source. It can also be run manually from the
Actions tab.

The workflow lives at [`.github/workflows/ios-testflight.yml`](../.github/workflows/ios-testflight.yml).

## One-time setup

### 1. App Store Connect API key

1. Go to App Store Connect -> Users and Access -> Integrations -> App Store
   Connect API -> Generate API Key.
2. Use `App Manager` access.
3. Download the `.p8` file.
4. Note the Issuer ID and Key ID.

### 2. Apple signing

CI expects one app bundle ID and one App Store provisioning profile:

| Target | Bundle ID | Provisioning profile name |
|---|---|---|
| Balm | `app.balm` | `Balm App Store` |

Create or download an Apple Distribution `.p12` certificate and an App Store
provisioning profile with the exact display name above.

### 3. GitHub secrets

Add these repository secrets under Settings -> Secrets and variables -> Actions:

| Secret name | Value |
|---|---|
| `APP_STORE_CONNECT_API_KEY_P8` | Full contents of the `AuthKey_XXXXXXXXXX.p8` file |
| `APP_STORE_CONNECT_API_KEY_ID` | 10-character Key ID |
| `APP_STORE_CONNECT_API_KEY_ISSUER_ID` | Issuer ID UUID |
| `APPLE_TEAM_ID` | 10-character Apple Developer Team ID |
| `IOS_DISTRIBUTION_CERTIFICATE_BASE64` | Base64-encoded `.p12` Apple Distribution certificate |
| `IOS_DISTRIBUTION_CERTIFICATE_PASSWORD` | Password used when exporting the `.p12` certificate |
| `IOS_BALM_PROFILE_BASE64` | Base64-encoded provisioning profile named `Balm App Store` |
| `IOS_KEYCHAIN_PASSWORD` | Temporary CI keychain password |

### 4. First run

Trigger `iOS · TestFlight` manually first. The signing step validates the
embedded provisioning profile name before archive, so a mismatched uploaded
profile fails early.

## Maintenance

- Bump `MARKETING_VERSION` in `project.yml` for app version changes.
- CI stamps `CURRENT_PROJECT_VERSION` from the GitHub run number so each
  TestFlight upload gets a unique build number.
- Rotate App Store Connect keys by updating the three
  `APP_STORE_CONNECT_API_KEY_*` secrets.
- Rotate signing assets by replacing the `.p12` and/or `.mobileprovision`
  secrets. Keep the provisioning profile name as `Balm App Store` unless you
  also update `Scripts/ci/ExportOptions.plist` and the workflow.
