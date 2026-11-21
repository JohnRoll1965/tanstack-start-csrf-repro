import { createFileRoute } from '@tanstack/react-router'
import { createServerFn } from '@tanstack/react-start'
import { useState } from 'react'

// Stands in for any write that must never accept a cross-origin request.
export const writeThing = createServerFn({ method: 'POST' })
  .validator((payload: string) => payload)
  .handler(async ({ data }) => {
    console.log(`[writeThing] wrote: ${data}`)
    return { ok: true, wrote: data }
  })

export const Route = createFileRoute('/')({
  component: Home,
})

function Home() {
  const [result, setResult] = useState('')
  return (
    <main>
      <h1>TanStack Start CSRF repro</h1>
      {/* repro.sh reads the server function's endpoint from here. */}
      <p>
        Server function endpoint: <code id="fn-url">{writeThing.url}</code>
      </p>
      <button
        onClick={async () => setResult(JSON.stringify(await writeThing({ data: 'from the page' })))}
      >
        Call writeThing from this page
      </button>
      <pre id="result">{result}</pre>
    </main>
  )
}
