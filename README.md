# Vitesse Nuxt Full-Stack Template

This repository adapts [antfu/vitesse-nuxt](https://github.com/antfu/vitesse-nuxt) into an npm workspace with two intentionally separate applications:

- `front-end/`: a statically generated Nuxt 4 application
- `back-end/`: a standalone Express 5 API

The browser always calls the API through the same-origin `/api` path. Local development, the two-container deployment, and Netlify each route that path to the Express application without enabling broad CORS access.

## Supported toolchain

- Node.js `24.18.1`
- npm `12.0.2`

Use the repository root for all package operations. The committed npm lockfile includes optional native packages for Linux ARM64 glibc and musl deployments, and npm rejects unreviewed dependency install scripts.

npm uses the nested install strategy so optional peer packages from unrelated tools cannot leak across workspace boundaries. Direct build-time type and lint dependencies are declared explicitly rather than relying on accidental hoisting.

```bash
npm ci
npm run server
npm run dev
```

The API listens on `127.0.0.1:3006` by default, while Nuxt listens on port `3333` and proxies `/api` to it. Copy `.env.example` only when local listener settings need to change.

## Validation

```bash
npm run audit:all
npm run audit:prod
npm run validate
npm run a11y
```

`npm run validate` checks Linux ARM64 lockfile entries, linting, type safety, API behavior, both production builds, and the expected deployment artifacts.

## API contract

The starter API is deliberately public and read-only:

- `GET /api/health` returns `{ "ok": true }` with no-store caching.
- `HEAD` and `OPTIONS` are permitted.
- Other methods return `405`, and unknown routes return JSON `404` responses.

There are no accounts, sessions, roles, promotion, or demotion workflows in this template. Do not infer authorization from the frontend, CORS, or a hidden route. Any downstream application that adds protected data must add authenticated, server-enforced authorization and tests at the Express boundary. See `docs/security-model.md`.

## Container deployment

The Dockerfile has two final targets: `api` and `frontend`. The frontend target serves static Nuxt output through an unprivileged Nginx process and proxies `/api` to the API service. The API target runs only compiled backend code as the unprivileged Node user and contains no npm, Corepack, or Yarn executables.

```bash
docker compose up --build
```

The application is then available on `http://127.0.0.1:8080`. Only the frontend port is published; the API remains on the private Compose network.

## Netlify deployment

Netlify generates the Nuxt frontend and bundles the same Express app as `netlify/functions/api.ts`. The first rewrite in `netlify.toml` sends `/api/*` to that function before the static SPA fallback. Node and npm versions are pinned in the repository and in Netlify configuration.

## Configuration

| Variable | Default | Purpose |
| --- | --- | --- |
| `HOST` | `127.0.0.1` | API listener address |
| `PORT` | `3006` | API listener port |
| `TRUST_PROXY_HOPS` | `0` | Number of explicitly trusted reverse-proxy hops; container and Netlify adapters set `1` |
| `DEV_API_ORIGIN` | `http://127.0.0.1:3006` | Nuxt development proxy target; it is never sent to browsers |

Do not commit secrets. This starter requires none.

## Git remotes

`origin` is the published monorepo template. `upstream` remains connected to `antfu/vitesse-nuxt` for selective upstream review; the workspace split is intentionally maintained locally.
