# Balm

A native, keyboard-driven SwiftUI client for **Jira Cloud** — built for a fast, Linear-style workflow on macOS and iOS.

Balm is **vendor-neutral**: your Jira site, projects, and credentials are all configured at runtime via Atlassian OAuth. Nothing organisation-specific is hardcoded, so any team can point it at their own Jira Cloud instance.

## Features

- Board and list views with full keyboard navigation
- Issue detail with rich ADF rendering (formatting, colours, tables, images)
- In-app image viewer for attachments
- Create, transition, assign, and edit issues
- Comments, attachments (upload + preview), labels, sprints, links
- Offline-aware, OAuth 2.0 (3LO) authentication

## Install (macOS)

Via [Homebrew](https://brew.sh):

```sh
brew tap kylescudder/tap
brew install --cask balm
```

> **A note on signing:** Balm is currently signed ad-hoc (not notarised with an Apple Developer ID). The cask strips the Gatekeeper quarantine flag on install (via a `postflight` step) so the app launches normally. Once a Developer ID + notarisation pipeline is in place this won't be necessary.

To update:

```sh
brew upgrade --cask balm
```

## Build from source

Requirements: macOS 15+, Xcode 16+, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
xcodegen generate     # generates Balm.xcodeproj from project.yml
open Balm.xcodeproj    # build & run the "Balm" scheme
```

The shared logic lives in the `BalmCore` Swift package (`Packages/BalmCore`) and can be built/tested independently:

```sh
cd Packages/BalmCore && swift build && swift test
```

### Auth backend (BFF)

OAuth token exchange requires a small backend (Atlassian's `/oauth/token` needs the client secret, which must never ship in the app). It lives in `Server/` and runs on [Bun](https://bun.sh):

```sh
cd Server
cp .env.example .env.local   # fill in your Atlassian OAuth app's CLIENT_ID + CLIENT_SECRET
bun install
bun run src/index.ts
```

Register your own OAuth 2.0 (3LO) app at <https://developer.atlassian.com/console/myapps/>, then set `ATLASSIAN_CLIENT_ID` in `App/Info.plist` and the `Server/.env.local` to match.

## Releases

Tagged releases (`vX.Y.Z`) are built by CI (`.github/workflows/release.yml`) and published to [GitHub Releases](https://github.com/kylescudder/balm/releases) as a zipped universal (`arm64` + `x86_64`) `.app`.

## License

Copyright © 2026 Kyle Scudder. All rights reserved.
