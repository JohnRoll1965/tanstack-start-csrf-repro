# TanStack Start: a start instance switches off default CSRF

**The claim.** TanStack Start protects server functions with a CSRF middleware by default, but only while your app has no start instance. The moment you create one with `createStart` (for a CSP nonce, a serializer, or any single request middleware), the default stops applying: a cross-origin POST to a state-changing server function succeeds. Nothing errors, no test fails, and the warning that would tell you only prints outside production. Re-adding `createCsrfMiddleware` first in `requestMiddleware` restores the protection. This repo proves all three states on the exact versions below, in one command.

## Pinned versions

| Package | Version |
| --- | --- |
| `@tanstack/react-start` | **1.168.41** |
| `@tanstack/react-router` | 1.170.24 |
| `@tanstack/start-server-core` (where the default lives) | 1.169.24 |
| `@tanstack/start-client-core` (`createCsrfMiddleware`) | 1.170.20 |
| `react`, `react-dom` | 19.2.8 |
| `vite` | 6.4.3 |
| `srvx` (production server) | 0.11.22 |
| Node | 22.21.1 |
| pnpm | 10.28.0 |

Every dependency is pinned exactly in `package.json`, the internal `@tanstack/*` packages are pinned through `pnpm.overrides`, and `pnpm-lock.yaml` is committed. These match the production app the claim was found in.

The app is the official `examples/react/start-basic` starter from the `@tanstack/react-start@1.168.41` tag of TanStack/router, stripped to one route and one server function, and run as a production build (`vite build`, then `node server.mjs`), not the dev server.

## Run it

```sh
pnpm install --frozen-lockfile
./repro.sh
```

`repro.sh` builds each state in turn, starts the production server on port 3311 (override with `PORT=`), and POSTs to the server function twice:

- **foreign origin:** `Origin: https://evil.example`
- **correct origin:** `Origin: http://localhost:3311`

curl sends no `Sec-Fetch-Site` header, which makes the CSRF check fall back to comparing `Origin` with the request's own origin. The request body is the exact one the page's own button sends (captured from Chrome). A CSRF rejection is a real `403 Forbidden` returned before the function runs, so the HTTP status is the signal. A 200 means `writeThing` ran and returned what it wrote.

Run one state with `./repro.sh b-bug`. The script puts your working copy of `src/start.ts` back when it finishes.

## The three states

Only one line of `src/start.ts` changes between them. Each is a tag.

| State | Tag | start instance | createCsrfMiddleware | foreign-origin POST | correct-origin POST |
| --- | --- | --- | --- | --- | --- |
| A | `a-baseline` | none | default on | 403 | 200 |
| B | `b-bug` | present, unrelated mw | absent | 200 written | 200 |
| C | `c-fix` | present | present, first | 403 | 200 |

```ts
// A: no start instance. This is exactly Start's own default entry
// (@tanstack/react-start/dist/plugin/default-entry/start.ts), used when src/start.ts is absent.
export const startInstance = undefined

// B: a start instance with one unrelated, do-nothing request middleware.
export const startInstance = createStart(() => ({ requestMiddleware: [unrelatedMiddleware] }))

// C: the same instance with CSRF re-added, first.
export const startInstance = createStart(() => ({ requestMiddleware: [csrfMiddleware, unrelatedMiddleware] }))
```

See it yourself with `git diff a-baseline b-bug` and `git diff b-bug c-fix`.

## Why it happens

In `@tanstack/start-server-core` 1.169.24, `dist/esm/createStartHandler.js`:

```js
const hasStartInstance = !!entries.startEntry.startInstance;
// ...
requestMiddleware: hasStartInstance ? startOptions.requestMiddleware : [defaultCsrfMiddleware],
```

The default CSRF middleware is used only when there is no start instance. Once there is one, its `requestMiddleware` replaces the default outright, so CSRF is yours to re-add. The warning that points this out is guarded by `process.env.NODE_ENV !== "production"`, so a production build never prints it.

## The fix

```ts
import { createCsrfMiddleware, createStart } from '@tanstack/react-start'

const csrfMiddleware = createCsrfMiddleware({
  filter: (ctx) => ctx.handlerType === 'serverFn',
})

export const startInstance = createStart(() => ({
  requestMiddleware: [csrfMiddleware /* , ...your other middleware */],
}))
```

Then prove it: a cross-site POST to any server function should return 403.

## Recorded output

`./repro.sh` on Linux, Node 22.21.1, after a clean `pnpm install --frozen-lockfile`:

```text
node v22.21.1, @tanstack/react-start 1.168.41

== a-baseline: export const startInstance = undefined
foreign origin (Origin: https://evil.example):  403 Forbidden
correct origin (Origin: http://localhost:3311): 200 ok, wrote: "same-site write"

== b-bug: export const startInstance = createStart(() => ({ requestMiddleware: [unrelatedMiddleware] }))
foreign origin (Origin: https://evil.example):  200 ok, wrote: "cross-site write"
correct origin (Origin: http://localhost:3311): 200 ok, wrote: "same-site write"

== c-fix: export const startInstance = createStart(() => ({ requestMiddleware: [csrfMiddleware, unrelatedMiddleware] }))
foreign origin (Origin: https://evil.example):  403 Forbidden
correct origin (Origin: http://localhost:3311): 200 ok, wrote: "same-site write"
```
