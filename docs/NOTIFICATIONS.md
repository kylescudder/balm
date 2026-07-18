# Notifications

## 1. Overview

Balm mirrors Jira's bell notifications: an issue you watch, reported, or are assigned to gets
updated, commented on, or transitioned — or an issue is assigned to you.

Jira Cloud exposes **no public API** for its in-product notification feed. The bell is backed by
an internal notification-log gateway that is only reachable with a browser session cookie, and
Atlassian staff have confirmed that third-party integration with it is not possible. Balm therefore
**synthesises** notifications from data the public REST API does expose.

Delivery happens in two phases:

| Phase | Mechanism | Status |
|---|---|---|
| 1 | In-app inbox + local system notifications, driven by polling | Implemented |
| 2 | Push notifications via the BFF (Jira dynamic webhooks → APNs) | Designed, not built |

## 2. Phase 1 — in-app notifications via polling (implemented)

### Query

`GET /rest/api/3/search/jql` with:

```
jql = (assignee = currentUser() OR reporter = currentUser() OR watcher = currentUser())
      AND updated >= -Nm ORDER BY updated DESC
```

plus `expand=changelog` and the `comment` field. The old `/rest/api/3/search` endpoint is dead
(removed October 2025); `/search/jql` is the supported endpoint.

The `updated >= -Nm` window uses **relative minutes**, which avoids JQL timezone pitfalls entirely.
`N` is computed from the last-poll cursor plus a 2-minute overlap, clamped to 3 minutes–14 days.
The overlap also absorbs the search index's eventual consistency.

### Diffing

`NotificationDiffer` (BalmAPI) is a pure function over the poll results. Per issue it inspects
changelog histories and new comments to derive events:

- `assignedToYou` — assignee changed to the current user
- `statusChanged` — status field transition
- `commented` — new comment on a covered issue
- `mentioned` — current user @mentioned in a comment
- `fieldUpdated` — other tracked field changes

Self-authored events are suppressed (you do not get notified about your own edits or comments).
Deduplication uses a bounded `seenIds` set, so re-fetching the overlap window never duplicates
notifications.

### Store and delivery

`InboxStore` (BalmFeatures) polls every 60–900 s with jitter and backoff, persists state to
`UserDefaults`, drives the Inbox UI, and optionally posts **local** system notifications via
`UNUserNotificationCenter` — which requires no entitlement or paid developer account.

### Cross-device read state

Each device previously stored read/unread state in local `UserDefaults` only, so reading a
notification on one device left it unread everywhere else. This is fixed with a small
conflict-free document synced through a Jira **user property** — per-user key/value storage on
the Atlassian account, not tied to any one device:

- `GET /rest/api/3/user/properties/balm-inbox-read-state?accountId=<me>` — `404` means the
  property was never set and is treated as an empty document, not an error.
- `PUT /rest/api/3/user/properties/balm-inbox-read-state?accountId=<me>` with the document as the
  raw JSON body — `200`/`201`, empty response body.

The document (`InboxReadState`, BalmAPI) is `{ readIds: [String], readAllBeforeEpoch: Double?,
updatedAtEpoch: Double? }`. `readIds` is a bounded FIFO capped at 500 entries (~15 KB worst case,
comfortably under the property's 32 KB limit); `readAllBeforeEpoch` is set by "mark all read" so
that action doesn't need to enumerate every id. Epoch fields are plain `Double`s (Unix seconds),
not `Date` — sidesteps any mismatch between `JSONDecoder.jira`'s Jira-specific date parsing and
the plain numeric encoder used for this property's body.

`InboxStore` pulls this property on every `syncNow()` and merges it into the local copy with a
commutative, idempotent **union** (union of `readIds` re-capped oldest-first, max of
`readAllBeforeEpoch`, max of `updatedAtEpoch`) — never last-write-wins, so no device's read marks
are lost to another device's stale copy. A pull only ever flips items unread → read, never the
reverse. Local mutations (`markRead`/`markUnread`/`markAllRead`) push the merged document back,
debounced ~3 s (bulk "mark all read" pushes immediately); if a pull's merge picked up local ids
the remote copy lacked, a push is scheduled so that device converges too.

This needs two new granular OAuth scopes — `read:user.property:jira` and
`write:user.property:jira` — which must also be enabled on the OAuth app in the Atlassian
developer console. Adding scopes forces existing sessions to re-consent before they take effect;
until then (or if the property endpoints ever answer `401`/`403`), sync silently disables itself
for the rest of the session and read state stays local-only — Settings surfaces a hint to sign out
and back in.

Known race: `markUnread` has no tombstone in the synced document (grow-only `readIds` union plus
the `readAllBeforeEpoch` watermark can't express a removal). The device where you unmarked keeps a
local-only exception set (`inbox.locallyUnread.v1`) so the item reliably stays unread there — even
under a prior mark-all-read watermark and across pulls — but *other* devices may still show it read.
Reading the item (or mark-all-read) clears its exception. Accepted rather than adding per-id
removal bookkeeping to the document.

### Known gaps

- **@mentions** are only detected on issues already covered by the JQL (assigned / reported /
  watched). A mention on an unrelated issue is missed.
- **Latency** — events are only as fresh as the poll interval.
- **Index lag** — the search index is eventually consistent; mitigated by the overlap window.

### Rate-limit impact

Negligible. Jira Cloud uses points-based hourly quotas; a search costs roughly 1 point. Per-user
polling consumes ~30–60 points/hour against tenant pools of 100k+ points/hour.

## 3. Phase 2 — push notifications via the BFF (designed, not yet built)

### Webhooks

The BFF registers **dynamic webhooks** (`POST /rest/api/3/webhook`) using each user's OAuth token.
The `jqlFilter` accepted there is a restricted subset: **no `currentUser()`** and **no `watcher`
field**. So the BFF registers per-user literal-accountId filters:

- `assignee = <accountId>`
- `reporter = <accountId>`

for events `jira:issue_created`, `jira:issue_updated`, `comment_created`, `comment_updated` —
using 2 of the 5-webhooks-per-user quota. The **watcher leg cannot be covered by webhooks** and
stays on polling.

Operational rules:

- Webhooks **expire every 30 days**. A BFF cron calls `PUT /rest/api/3/webhook/refresh` roughly
  every 14 days; expired webhooks are recoverable for 3 months.
- Deliveries carry an **HS256 JWT** signed with the app's client secret — the BFF must verify it.
- There is **no delivery-failure API** for OAuth apps, so a reconciliation poll is kept as backstop.
- **Scope changes** required: `write:webhook:jira`, `read:webhook:jira`, `delete:webhook:jira`
  (plus `read:field:jira` and `read:project:jira`, already held). Adding scopes forces **all users
  to re-consent** — batch the change once.
- Caveat: while the OAuth app is non-public (distribution off), webhooks only deliver for
  registrations made by the **app owner**.

### BFF additions (Bun/Hono, `Server/src`)

- `POST` / `DELETE` `/api/devices` — device-token registry keyed by `accountId` + `cloudId`.
- `POST /api/jira/webhook` — receiver: verify JWT → map `matchedWebhookIds` → user → device tokens.
- APNs sender over HTTP/2 — token-based `.p8` auth against `api.push.apple.com`. Use `node:http2`
  in Bun; plain `fetch` will not do HTTP/2 client requests.
- `apns-collapse-id` per issue key, so repeated updates coalesce.
- Prune device tokens on APNs `410` responses.

### App-side work

- `aps-environment` entitlement and `UIBackgroundModes: remote-notification` (iOS) via `project.yml`.
- Call `registerForRemoteNotifications` and upload the device token to the BFF.

### Blocker

APNs requires the `aps-environment` entitlement backed by an Apple-issued provisioning profile —
i.e. the paid Apple Developer Program ($99/yr). Balm is currently ad-hoc signed, so
`registerForRemoteNotifications` cannot succeed. Local notifications (Phase 1) are the interim.

## 4. Decision log

| Mechanism | Verdict | Reason |
|---|---|---|
| In-product notification feed | Rejected | No public API; internal gateway, session-cookie only |
| Admin webhooks (`/rest/webhooks/1.0`) | Rejected | Requires Administer Jira; no per-user context |
| Forge triggers | Rejected | Forge-hosted apps only; Balm is an external client |
| Polling `/search/jql` | **Chosen (Phase 1)** | Works with existing scopes; covers watcher; no entitlements |
| Dynamic webhooks + APNs via BFF | **Planned (Phase 2)** | Real-time push; needs new scopes + paid Apple account |

### References

- Webhooks: <https://developer.atlassian.com/cloud/jira/platform/webhooks/>
- Search (JQL): <https://developer.atlassian.com/cloud/jira/platform/rest/v3/api-group-issue-search/#api-rest-api-3-search-jql-get>
- Rate limiting: <https://developer.atlassian.com/cloud/jira/platform/rate-limiting/>
- APNs entitlement: <https://developer.apple.com/documentation/bundleresources/entitlements/aps-environment>
