// Production entry: runs the built fetch handler on Node with srvx and serves the client assets.
// Same shape as the production app this repro mirrors.
import { serve } from 'srvx'
import { serveStatic } from 'srvx/static'

const { default: app } = await import('./dist/server/server.js')

serve({
  port: Number(process.env.PORT ?? 3000),
  hostname: '127.0.0.1',
  middleware: [serveStatic({ dir: new URL('./dist/client', import.meta.url).pathname })],
  fetch: app.fetch,
})
