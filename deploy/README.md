# Balm auth on Herman

Every push to `main` runs **Deploy auth**, including changes outside `Server/`.
CI tests and typechecks the BFF, tests the webhook and deployer, builds native
AMD64/ARM64 images, publishes `ghcr.io/kylescudder/balm-auth`, and attests the
immutable manifest. A signed webhook asks Herman to deploy it. The workflow
succeeds only when public `/health` reports that exact commit.
The existing tagged macOS Release and iOS/TestFlight workflows are independent.

## Host and public URLs

- Checkout: `/Users/kyle/platform/apps/balm-auth` on `herman.local` / `herman-1`.
- Auth: `https://balm-auth.kylescudder.co.uk`, upstream `balm-auth:3000`.
- Hook: `https://balm-deploy.kylescudder.co.uk/hooks/balm-auth`.
- LaunchAgent: `com.herman.balm-auth-deploy`, running as Kyle, the Colima owner.
- Runtime: Bun 1.3.13 pinned by digest; no database or persistent application volume.

The old nested auth hostname is not switched by this deployment. Existing app
binaries retain their compiled BFF URL and need an updated build to use the new
hostname. Custom `Config/Secrets.xcconfig` or `IOS_SECRETS_XCCONFIG` overrides
must also use the new URL. OAuth client ID, secret and `balm://auth/callback`
remain the same. Full sign-in and existing-token refresh require real device
acceptance; health and synthetic tests do not establish that acceptance.

## Trust boundaries

The receiver has no Docker socket, shell credentials, database network or host
ports. It has a read-only filesystem and can write only its request queue.
HMAC-SHA256 signatures, a five-minute timestamp window, bounded request sizes
and a bounded queue protect the exact webhook route. Unlike Spooktober, this
separate hostname currently has no Cloudflare Access layer. Do not describe it
as Access-protected. Unrelated paths return 404, unsigned hook requests 401.

The host independently verifies GitHub provenance for `kylescudder/balm`,
`.github/workflows/deploy-auth.yml`, `refs/heads/main`, and GitHub-hosted runners.
It checks the OCI revision, starts the exact digest and waits for health.
Failed candidates restore the previous image. Deployments are serialized and
queue snapshots coalesce to the newest request. GitHub's release concurrency
keeps successive main runs in order (GitHub may replace intermediate pending
runs with the newest push). Manual rollback accepts only an attested main digest.

## Configuration

GitHub's `production` environment permits branch `main` only and has no required
reviewer. Its only secret is `DEPLOY_WEBHOOK_SECRET`. Repository variables:

- `DEPLOY_ENABLED=true` enables deployment after publication.
- `AUTH_BASE_URL=https://balm-auth.kylescudder.co.uk` selects public verification.

On Herman, `.env` holds the immutable `BALM_AUTH_IMAGE`, `ATLASSIAN_CLIENT_ID`,
`ATLASSIAN_CLIENT_SECRET` and optional `PLATFORM_WEB_NETWORK`.
`.env.deploy-hook` holds the queue/secret paths and UID/GID 501:20.
`secrets/deploy-webhook-secret` is the HMAC key. Files are 0600, private
folders 0700, and all are ignored by Git. Atlassian credentials never enter
GitHub, the image, build context or webhook. Shared encrypted NAS backups cover
these files, deployment tools and the successful release/history records.

## Commands

From the checkout:

```sh
docker compose -f deploy/compose.deploy-hook.yaml --env-file .env.deploy-hook up -d --wait
python3 -B deploy/install-launchd.py
launchctl print gui/501/com.herman.balm-auth-deploy
tail -n 100 state/deploy.log
./deploy/herman-deploy.sh sha256:<verified-main-digest>
```

Pause requests with `gh variable set DEPLOY_ENABLED --body false --repo kylescudder/balm`.
The manual command remains available. Successful deployments persist the image
into `.env` so ordinary Compose recreation retains the selected digest.

Application code is delivered inside each image. Host `deploy/` tooling and
Compose changes require a reviewed checkout update and, where relevant,
receiver recreation or LaunchAgent reinstallation; running repository-provided
host scripts automatically from every downloaded image would cross the trust
boundary. Keep changes to these files separate from routine BFF releases.

No self-hosted GitHub runner is installed. Kyle's login session and Colima must
be running; FileVault requires unlock after a host reboot. Use the platform
runbook and Herman skills for health, backups, hostnames and recovery.
