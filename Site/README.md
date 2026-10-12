# Balm site

Static site for getbalm.app — landing page plus the privacy,
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

## Hosting

Every push to main builds an attested image and deploys to Herman through an
Access-protected webhook. See [marketing deployment](../deploy/site/README.md).
The public site is `https://getbalm.app`. Netlify builds are disabled; its old
published copy is retained only for rollback.

## URLs for the Atlassian developer console

| Field                    | URL                         |
| ------------------------ | --------------------------- |
| Privacy policy           | https://getbalm.app/privacy |
| Terms of service         | https://getbalm.app/terms   |
| Customer support contact | https://getbalm.app/support |
