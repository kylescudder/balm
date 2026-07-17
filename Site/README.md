# Balm site

Static site for balm.kylescudder.co.uk — landing page plus the privacy,
terms, and support pages Atlassian's app distribution form requires.
Built with Astro. The generated site is static and ships no client-side
JavaScript.

## Local preview

Install dependencies once:

```sh
cd Site
bun install
```

Run the development server:

```sh
bun run dev
```

Then open `http://localhost:4321/`.

## Build

```sh
bun run build
```

The deployable files are written to `dist/`.

## Hosting with Caddy

1. Run `bun run build`.
2. Copy the contents of `dist/` to the server, e.g. `/var/www/balm`.
3. Merge `Caddyfile` into your Caddy config (adjust domain/root if needed).
4. Reload Caddy: `caddy reload` (or `systemctl reload caddy`).

`try_files {path} {path}/index.html {path}.html` gives the clean URLs below.

## URLs for the Atlassian developer console

| Field | URL |
|---|---|
| Privacy policy | https://balm.kylescudder.co.uk/privacy |
| Terms of service | https://balm.kylescudder.co.uk/terms |
| Customer support contact | https://balm.kylescudder.co.uk/support |
