// The only file that changes between the three states. See README.md.
import { createCsrfMiddleware, createMiddleware, createStart } from '@tanstack/react-start'

// Unrelated request middleware: it does nothing but pass the request on. Any real reason to
// create a start instance (a CSP nonce, a serializer, logging) has the same effect.
const unrelatedMiddleware = createMiddleware({ type: 'request' }).server(({ next }) => next())

// The same CSRF middleware Start applies by default when there is no start instance.
const csrfMiddleware = createCsrfMiddleware({
  filter: (ctx) => ctx.handlerType === 'serverFn',
})

// The one line that differs between the states (tags a-baseline, b-bug, c-fix):
//   A: `undefined`, no start instance. Exactly the framework's own default entry
//      (@tanstack/react-start/dist/plugin/default-entry/start.ts), used when src/start.ts is absent.
//   B: a start instance with only the unrelated middleware. Default CSRF is gone.
//   C: the same instance with csrfMiddleware re-added, first.
export const startInstance = createStart(() => ({ requestMiddleware: [csrfMiddleware, unrelatedMiddleware] }))
