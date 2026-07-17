# Balm site

Static site for balm.kylescudder.co.uk — landing page plus the privacy,
terms, and support pages Atlassian's app distribution form requires.
No build step, no JavaScript, no external assets.

## Hosting with Caddy

1. Copy the contents of this directory to the server, e.g. `/var/www/balm`.
2. Merge `Caddyfile` into your Caddy config (adjust domain/root if needed).
3. Reload Caddy: `caddy reload` (or `systemctl reload caddy`).

`try_files {path} {path}.html` gives the clean URLs below.

## URLs for the Atlassian developer console

| Field | URL |
|---|---|
| Privacy policy | https://balm.kylescudder.co.uk/privacy |
| Terms of service | https://balm.kylescudder.co.uk/terms |
| Customer support contact | https://balm.kylescudder.co.uk/support |
