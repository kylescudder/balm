# Balm marketing on Herman

`https://getbalm.app` serves the static Astro output from `Site/` in a small
Caddy container. Every push to main runs `deploy-site.yml`: build/format checks,
AMD64 and ARM64 image builds, publication of `ghcr.io/kylescudder/balm-site`,
GitHub provenance attestation, a signed webhook and public revision acceptance.
The auth workflow is independent and both run on main changes.

## Configuration and security

Checkout: `/Users/kyle/platform/apps/balm-site`. Compose: `compose.site.yaml`.
App upstream: `balm-site:8080` on `platform-web`. No database or host port.
Receiver: `balm-site-deploy-hook:9000`, on the same web network, with no Docker
socket and only a writable queue. Its public route is exactly
`https://deploy-site.getbalm.app/hooks/balm-site`.

Cloudflare Access covers the whole `deploy-site.getbalm.app` hostname with
application `Balm site deploy` and one Service Auth policy including only
`github-balm-site-deploy`. The 401 response for Service Auth policies is enabled.
The public website itself has no Access policy. The workflow checks edge denial,
authenticated 404s for unrelated paths, receiver denial of a bad HMAC, and the
actual deployed revision. These gates fail closed if Access is missing.

GitHub environment `marketing-production` allows branch main only. Secrets:
`CF_ACCESS_CLIENT_ID`, `CF_ACCESS_CLIENT_SECRET` (one-year dedicated Access
token), and `DEPLOY_WEBHOOK_SECRET`. Variables `SITE_DEPLOY_ENABLED=true` and
`SITE_BASE_URL=https://getbalm.app` enable requests and public verification.

Host `.env` pins `BALM_SITE_IMAGE` and `PLATFORM_WEB_NETWORK`. `.env.deploy-hook`
contains absolute queue/secret paths and UID/GID 501:20.
`secrets/deploy-webhook-secret` holds the separate HMAC key. Files are 0600,
private directories 0700, and excluded from Git. No auth backend credential is
copied into the marketing checkout or image.

`com.herman.balm-site-deploy` is an event-driven launchd agent, running as
Kyle (the Colima owner). It verifies image provenance for this repository's
`deploy-site.yml`, main and hosted runners before applying a digest. Failed
health checks restore the previous image; each success pins the digest in `.env`
and records it in `state/`. It does not poll GitHub or run a self-hosted runner.

## Operate

From the checkout:

```sh
docker compose -f deploy/site/compose.deploy-hook.yaml --env-file .env.deploy-hook up -d --wait
python3 -B deploy/site/install-launchd.py
launchctl print gui/501/com.herman.balm-site-deploy
tail -n 100 state/deploy.log
./deploy/site/herman-deploy.sh sha256:<verified-main-digest>
```

Pause with `gh variable set SITE_DEPLOY_ENABLED --body false --repo kylescudder/balm`.
Host deploy tooling and Compose changes need a reviewed checkout update; runtime
site changes ship inside each image. Kyle must be logged in and Colima running.
The encrypted platform NAS backup includes config, secrets, deploy tooling,
Compose and release records; image/site files are recovered from attested builds.

Netlify builds are skipped by the repository's `netlify.toml` ignore command.
The old published Netlify site is retained only for rollback, not used by the
new domain. No Netlify account resources are deleted by this migration.
