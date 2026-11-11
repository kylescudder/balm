# Balm website

The static Astro home, privacy, terms and support pages for Balm, including the
pages Atlassian's app distribution form requires. It ships no client-side
JavaScript. Public hostname: **getbalm.app** (and `www.getbalm.app`).

## Development

Use Bun 1.4.4. From `Site/`, install the committed dependencies with
`bun install --frozen-lockfile`. This also installs the pre-commit hook.

```sh
bun run dev
```

Open **http://localhost:4321**. The site has no runtime configuration or
backend.

## Checks

See [CONTRIBUTING.md](CONTRIBUTING.md). In short:

```sh
bun run format:check
bun run lint
bun run typecheck
bun run build
bun run check:site   # pages, the auth service in the privacy policy, built assets
```

## Deployment

Merging a change under `Site/` to `main` runs `deploy-site.yml`: it repeats the
checks, builds an attested AMD64/ARM64 image (`ghcr.io/kylescudder/balm-site`)
and asks Herman's deploy-core service to deploy that digest through
`https://deploy-site.getbalm.app/hooks/balm-site`. The image serves `dist/` from
an unprivileged, read-only Caddy container on port 8080 and reports the deployed
commit in `X-Balm-Site-Revision` on `/healthz`. Herman checks the attestation and
the pages before switching and keeps the previous image for rollback. The
workflow waits until Herman acknowledges the image and the public site reports
the new commit. Run the workflow manually to redeploy.

The main-only `marketing-production` environment holds `CF_ACCESS_CLIENT_ID`,
`CF_ACCESS_CLIENT_SECRET` and `DEPLOY_WEBHOOK_SECRET`. The repository variables
`SITE_DEPLOY_ENABLED=true` and `SITE_BASE_URL` turn on the deploy job and name
the public origin it checks. Host setup and recovery are in Herman's platform
runbook.

## URLs for the Atlassian developer console

| Field                    | URL                         |
| ------------------------ | --------------------------- |
| Privacy policy           | https://getbalm.app/privacy |
| Terms of service         | https://getbalm.app/terms   |
| Customer support contact | https://getbalm.app/support |
