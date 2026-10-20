# Balm auth on the host

## Shared deployment service

This app is registered as `balm-auth` in the central deployment registry
`/Users/kyle/platform/deploy-core/apps.json`. LaunchAgent
`com.kylescudder.deploy-core` runs the single installed engine. Application hooks
are not needed; the receiver, credentials, queues,
state and database contracts below remain app-specific. Manual deployment uses
`./deploy/host-deploy.sh sha256:<digest>`.

Engine updates, application registration, failure inspection and service rollback
are documented in [deploy-core](https://github.com/kylescudder/deploy-core).
There are no vendored engine files, lock files or sync PRs. Do not install an
app-specific LaunchAgent. Apply future engine changes once through the central service.


Every push to `main` runs **Deploy auth**, including changes outside `Server/`.
CI tests and typechecks the BFF, tests the webhook and deployer, builds native
AMD64/ARM64 images, publishes `ghcr.io/kylescudder/balm-auth`, and attests the
immutable manifest. A signed webhook asks the host to deploy it. The workflow
succeeds only when public `/health` reports that exact commit.
The existing tagged macOS Release and iOS/TestFlight workflows are independent.

## Host and public URLs

- Checkout: `/Users/kyle/platform/apps/balm-auth` on the host.
- Auth: `https://auth.getbalm.app`, upstream `balm-auth:3000`.
- Hook: `https://deploy-auth.getbalm.app/hooks/balm-auth`.
- LaunchAgent: `com.kylescudder.deploy-core`, running as Kyle, the Colima owner.
- Deployer: the centrally installed service; application behavior lives in `hooks.py`.
- Runtime: Bun 1.3.13 pinned by digest; no database or persistent application volume.

Native builds use `https://auth.getbalm.app`. Previously installed binaries keep
their compiled BFF URL and need an updated build for the new domain. Custom
`Config/Secrets.xcconfig` and `IOS_SECRETS_XCCONFIG` overrides must also use this
URL. The OAuth application and `balm://auth/callback` remain unchanged. Real
device sign-in and refresh acceptance are distinct from deployment checks.
The marketing pipeline is documented in [site/README.md](site/README.md).

## Trust boundaries

The receiver has no Docker socket, shell credentials, database network or host
ports. It has a read-only filesystem and can write only its request queue.
HMAC-SHA256 signatures, a five-minute timestamp window, bounded request sizes
and a bounded queue protect the exact webhook route. Cloudflare Access must
protect the whole `deploy-auth.getbalm.app` hostname with a Service Auth
policy allowing only `github-balm-auth-deploy`. Enable the Service Auth 401
response. Never protect the native app's `auth.getbalm.app` endpoint
with this policy: the native client cannot send deployment credentials.

Before requesting a deployment, the workflow verifies that unauthenticated
requests are denied before reaching the receiver, authenticated unrelated
paths return 404, and a valid Access token with an invalid HMAC reaches the
receiver but is rejected with 401. It then sends both credentials with the
signed deployment request. A receiver marker distinguishes its own 401 from
Cloudflare's denial. These checks fail closed when Access or secrets are absent.

The host independently verifies GitHub provenance for `kylescudder/balm`,
`.github/workflows/deploy-auth.yml`, `refs/heads/main`, and GitHub-hosted runners.
It checks the OCI revision, starts the exact digest and waits for health.
Failed candidates restore the previous image. Deployments are serialized and
queue snapshots coalesce to the newest request. GitHub's release concurrency
keeps successive main runs in order (GitHub may replace intermediate pending
runs with the newest push). Manual rollback accepts only an attested main digest.

## Configuration

GitHub's `production` environment permits branch `main` only and has no required
reviewer. Its secrets are `DEPLOY_WEBHOOK_SECRET`, `CF_ACCESS_CLIENT_ID` and
`CF_ACCESS_CLIENT_SECRET`. The Access values belong to the dedicated
`github-balm-auth-deploy` service token; set its duration to one year and record
its expiry during provisioning. Store them directly in GitHub's production
environment, never in repository files or chat. Repository variables:

- `DEPLOY_ENABLED=true` enables deployment after publication.
- `AUTH_BASE_URL=https://auth.getbalm.app` selects public verification.

On the host, `.env` holds the immutable `BALM_AUTH_IMAGE`, `ATLASSIAN_CLIENT_ID`,
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
launchctl print gui/501/com.kylescudder.deploy-core
tail -n 100 state/deploy.log
./deploy/host-deploy.sh sha256:<verified-main-digest>
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
runbook and the host skills for health, backups, hostnames and recovery.

## Provision Cloudflare Access

In Cloudflare One, create a service token named `github-balm-auth-deploy` with
a one-year duration. Copy its Client ID and Client Secret into the two Access
secrets in GitHub's `production` environment (the secret is shown only once).
Create a Self-hosted Access application named `Balm deploy`, public hostname
`deploy-auth.getbalm.app`, with no path restriction. Add one policy named
`GitHub Balm deploy`, action `Service Auth`, Include selector `Service Token`,
value `github-balm-auth-deploy`. Do not add Allow Everyone or Bypass policies.
Enable the application's 401 response for Service Auth policies.

During installation, keep `DEPLOY_ENABLED=false` until the policy and secrets
exist and unauthenticated requests no longer reach the receiver. Merge the
Access-aware workflow, re-enable requests, and run Deploy auth on main to
verify the complete path. Do not mark Access accepted until that deployment's
protection checks and public revision check pass. Rotate/renew the Access token
before expiry, updating both GitHub secrets together.

New native builds use `https://auth.getbalm.app`. TestFlight explicitly applies
that URL after loading private build configuration, so a stale config secret
cannot retain the previous hostname. Installed binaries need an update.
