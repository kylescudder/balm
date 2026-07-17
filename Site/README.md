# Balm site

Static site for balm.kylescudder.co.uk — landing page plus the privacy,
terms, and support pages Atlassian's app distribution form requires.
Built with Astro. The generated site is static and ships no client-side
JavaScript.

## Local preview

Install dependencies once:

```sh
bun install --cwd Site
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

## Netlify

The `Site/` directory owns the Astro package. The repository root only
delegates commands into it, so Netlify should still use the root package and
the checked-in `netlify.toml`:

```text
Base directory:      leave blank
Package directory:   leave blank
Build command:       bun run build
Publish directory:   Site/dist
Functions directory: leave blank
```
## URLs for the Atlassian developer console

| Field | URL |
|---|---|
| Privacy policy | https://balm.kylescudder.co.uk/privacy |
| Terms of service | https://balm.kylescudder.co.uk/terms |
| Customer support contact | https://balm.kylescudder.co.uk/support |
