# AGENTS.md

This file provides guidance to coding agents when working with code in this repository.

## Project

Balm is a native SwiftUI client for Jira Cloud, targeting iOS/iPadOS 18+ and macOS 15+. It provides project-scoped list and board workflows, issue creation and editing, Atlassian Document Format rendering, attachments, comments, filters, and a polling-based notification inbox. The repository also contains a small Bun/Hono OAuth BFF and a static Astro marketing and compliance site.

## Common commands

The Xcode project is generated from `project.yml` and is git-ignored. Regenerate it after any app source, package, target, signing, or dependency change.

```sh
cp Config/Secrets.xcconfig.example Config/Secrets.xcconfig
xcodegen generate
open Balm.xcodeproj
xcodebuild build \
  -project Balm.xcodeproj \
  -scheme Balm \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO
./setup.sh
```

The local Swift package has the iOS logic and test suites:

```sh
swift build --package-path Balm/BalmCore
swift test --package-path Balm/BalmCore
```

OAuth BFF:

```sh
cp Server/.env.example Server/.env.local
cd Server
bun install
bun run dev
bun test
bun run typecheck
```

Marketing site:

```sh
bun run dev
bun run build
bun run preview
cd Site && bun run format:check
```

There is no Swift linter or formatter configured. Do not invent additional validation commands. Run the package tests for logic changes, the generated-project build for app wiring changes, and the Astro/BFF checks for their respective surfaces.

## Secrets and configuration

- Native build configuration lives in `Config/Secrets.xcconfig` (git-ignored and copied from `Config/Secrets.xcconfig.example`). `project.yml` attaches it to Debug and Release, and `Balm/Info.plist` exposes `ATLASSIAN_CLIENT_ID` and `BALM_BFF_BASE_URL` to `AppEnvironment`. An xcconfig URL must escape `//` as `/$()/`, for example `https:/$()/example.com`, because unescaped `//` begins a comment.
- The Atlassian client ID and BFF URL are embedded in the app and are not confidential. The Atlassian client secret is confidential and belongs only in `Server/.env.local` or the deployed BFF environment. Never add the client secret to the xcconfig, plist, Swift source, site, tests, or logs.
- The BFF loads `ATLASSIAN_CLIENT_ID`, `ATLASSIAN_CLIENT_SECRET`, and optional `PORT` from its environment. It exists because Atlassian's token exchange and refresh require the client secret even when the native client uses PKCE.
- TestFlight signing material and App Store Connect credentials are GitHub Actions secrets. `IOS_SECRETS_XCCONFIG` can supply the production native config; pull-request builds use the committed example.

## Architecture

### Repository and app composition

- `Balm/` is the top-level native application directory. The app target compiles the entry point, plist, entitlements, and asset catalog directly under that folder.
- `Balm/BalmCore/` is a local Swift package nested with the app but excluded from the app target's raw source list. Xcode links its library products through the `BalmCore` package dependency declared in `project.yml`; do not also add package sources directly to the app target.
- `BalmApp` creates one Observation-based `AppEnvironment`, injects it with SwiftUI's `environment`, and applies the shared Balm theme. `RootView` is intentionally thin and delegates auth-state routing to `AppRootView`.
- `AppEnvironment` is the composition root. It owns `AtlassianOAuth`, `TokenStore`, `JiraClient`, `NetworkMonitor`, `Toaster`, `ActiveProjectStore`, and `InboxStore`. Keep shared service lifecycle and account transitions there rather than constructing parallel service graphs in views.
- `AppRootView` switches between loading, signed-out, and signed-in states. `MainShellView` owns project selection, issue-detail presentation, settings, and the inbox. macOS uses an inspector-oriented layout; iOS/iPadOS presents issue detail in a native sheet.

### Swift package boundaries

- `BalmModels` contains transport-independent Jira models and filter definitions.
- `BalmAuth` owns PKCE, the web-authentication session, Keychain access, stored auth, refresh, and OAuth configuration.
- `BalmAPI` owns typed Jira endpoints, request execution, pagination, raw response mapping, and notification-diff primitives. Keep JSON quirks and Jira response normalization in this layer rather than in views.
- `BalmADF` parses and renders Atlassian Document Format models.
- `BalmPersistence` is the persistence boundary; it is intentionally small today. New durable storage should remain behind this target instead of leaking storage details into features.
- `BalmDesignSystem` owns the palette, typography, spacing, cards, buttons, chips, and theme environment. Reuse these primitives before adding one-off visual constants.
- `BalmFeatures` owns SwiftUI screens, view models, feature stores, navigation surfaces, and app composition. It may depend on all lower layers; lower targets must not depend back on it.

### Authentication and Jira API

- `AtlassianOAuth` uses `ASWebAuthenticationSession` with PKCE and the callback `balm://auth/callback`. Authorization happens against Atlassian, while code exchange and refresh go through the configured BFF. Keep the BFF request/response contracts aligned with `Server/src/index.ts`.
- `OAuthConfig.atlassian` is the single scope list. Any endpoint addition that needs another permission requires updating this list and enabling the same granular scope in the Atlassian developer console. Do not mix classic and granular Jira scopes.
- `TokenStore` persists tokens in Keychain and owns refresh behavior. A permanently rejected rotating refresh token posts the session-expired notification handled by `AppRootView`; transient network failures must not be treated as sign-out.
- `JiraClient` is the shared authenticated transport. Add typed endpoint definitions under `BalmAPI/Endpoints`, map Jira wire shapes under `BalmAPI/Mapping`, and keep views consuming stable `BalmModels` values.
- The selected Jira cloud resource and current user are established during sign-in/bootstrap. `ActiveProjectStore` is reset on sign-out so a different account cannot inherit the prior account's project context.

### Issues, filters, and mutations

- `IssueListViewModel` coordinates list loading, cache policy, cancellation, and board/list presentation. Preserve request identity checks when changing async refresh behavior so stale results cannot replace a newer project or filter.
- `FilterStore`, `SavedFiltersStore`, and `ActiveProjectStore` own their respective user choices. Use the existing `FilterQuery`/JQL builder path instead of assembling ad hoc JQL in views.
- Issue detail reads and mutations belong in `IssueDetailViewModel` plus typed endpoint definitions. After a mutation, update or refetch the authoritative issue state so the list, board, and detail surfaces do not diverge.
- ADF descriptions/comments and attachment media have dedicated renderer and image-viewer paths. Do not flatten ADF to plain text when structured content is available, and keep authenticated Jira media requests going through the API layer.

### Notification inbox

- Jira Cloud exposes no supported equivalent of its bell-notification feed. Balm's current inbox is synthesized client-side by polling enhanced issue search for activity on issues where the current user is assignee, reporter, or watcher.
- `InboxStore` owns the poll loop, local persistence, optional local system notifications, paging, backoff, and account isolation. It defaults to 120 seconds, supports the intervals in `allowedPollIntervals`, uses jitter, and backs off to 15 minutes after failures.
- `NotificationSyncWindow` and `NotificationDiffer` share a two-minute overlap and bounded dedupe state. Preserve that relationship when changing cursor behavior; moving the cursor beyond unfetched pages can silently lose events.
- First-run history is backfilled as read. Read state is merged across devices through a Jira user property when the OAuth token has the required user-property scopes; a 401/403 intentionally falls back to local-only read state for that app session.
- Mentions on unrelated issues are not discoverable with the current search and polling is not real-time. Webhook/APNs support is planned but not implemented; do not describe the current inbox as push-backed.

### BFF and marketing site

- `Server/` is a Bun/Hono service with only native token exchange, token refresh, and health endpoints. It must keep the Atlassian client secret server-side. CORS is currently broad; treat any expansion beyond token brokering as a security-sensitive server change.
- `Site/` is a static Astro site. `BaseLayout` owns global structure, document metadata, header, and footer; privacy, terms, and support are product behavior contracts and must track changes to authentication, data handling, analytics, notifications, and support contact behavior.
- Netlify builds with base `Site`, command `bun run build`, and publish directory `Site/dist`. Its ignore rule skips deploys when neither the site nor `netlify.toml` changed.
- Runtime artwork belongs with its consumer: native assets in `Balm/Assets.xcassets`, web assets in `Site/public/assets`. There is no separate top-level branding source directory.

## Strict concurrency

Swift 6 language mode and `SWIFT_STRICT_CONCURRENCY: complete` are enabled. `AppEnvironment`, feature stores, and UI-facing view models are generally `@MainActor`; transport and model values crossing isolation boundaries must be `Sendable`. `ASWebAuthenticationSession` callbacks have deliberate nonisolated handling. Do not silence concurrency findings with `@unchecked Sendable` without a concrete thread-safety justification.

## SDK and contract drift

- Atlassian REST wire formats are inconsistent around missing/null fields, pagination, and ADF. Update the relevant raw mapping type and its tests instead of spreading permissive decoding through feature code.
- The OAuth app's enabled permissions, `OAuthConfig` scope list, BFF contract, callback URL type in `Info.plist`, and server environment must remain aligned.
- Astro and Prettier dependencies are pinned by `Site/bun.lock`. Keep that lockfile with intentional updates and run both the production build and `format:check`.
- The generated Xcode project and package resolution are not committed. Changes to `project.yml` must be validated by regenerating before diagnosing the generated project.

## Folder casing

The app folder is `Balm/`, the nested package is `Balm/BalmCore/`, the marketing site is `Site/`, and the OAuth backend is `Server/`. Preserve those spellings in source, scripts, workflows, and documentation so the repository remains portable to case-sensitive filesystems.

## What not to commit

Do not commit `Config/Secrets.xcconfig`, local `Server/.env*` files other than the example template, `Balm.xcodeproj/`, `build/`, `DerivedData/`, `.build/`, `.swiftpm/`, `Package.resolved`, `node_modules/`, `Site/.astro/`, `Site/dist/`, `.netlify/`, signing certificates, provisioning profiles, or App Store Connect keys. These are git-ignored where applicable; do not add overrides.
