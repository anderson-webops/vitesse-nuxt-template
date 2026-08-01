import { createServer } from 'node:http'
import process from 'node:process'
import 'dotenv/config'

import { createApp } from './app.js'

function parseInteger(name: string, rawValue: string | undefined, fallback: number, minimum: number, maximum: number) {
  if (rawValue === undefined || rawValue === '')
    return fallback

  const value = Number(rawValue)
  if (!Number.isSafeInteger(value) || value < minimum || value > maximum)
    throw new RangeError(`${name} must be an integer between ${minimum} and ${maximum}`)

  return value
}

async function main() {
  const port = parseInteger('PORT', process.env.PORT, 3006, 1, 65_535)
  const trustProxyHops = parseInteger('TRUST_PROXY_HOPS', process.env.TRUST_PROXY_HOPS, 0, 0, 2)
  const host = process.env.HOST || '127.0.0.1'
  const server = createServer(createApp({ trustProxyHops }))

  server.headersTimeout = 10_000
  server.keepAliveTimeout = 5_000
  server.maxHeadersCount = 100
  server.maxRequestsPerSocket = 1_000
  server.requestTimeout = 15_000

  await new Promise<void>((resolve, reject) => {
    server.once('error', reject)
    server.listen(port, host, resolve)
  })

  console.log(`API listening at http://${host}:${port}`)

  let isShuttingDown = false
  const shutdown = (signal: NodeJS.Signals) => {
    if (isShuttingDown)
      return

    isShuttingDown = true
    console.log(`${signal} received; closing the API server`)

    const forceTimer = setTimeout(() => {
      console.error('Graceful shutdown timed out; closing active connections')
      server.closeAllConnections()
      process.exitCode = 1
    }, 10_000)
    forceTimer.unref()

    server.close((error) => {
      clearTimeout(forceTimer)
      if (error) {
        console.error('Graceful shutdown failed:', error)
        process.exitCode = 1
        return
      }

      console.log('API shutdown complete')
    })
    server.closeIdleConnections()
  }

  process.once('SIGINT', () => shutdown('SIGINT'))
  process.once('SIGTERM', () => shutdown('SIGTERM'))
}

main().catch((error) => {
  console.error('Unable to start the API:', error)
  process.exitCode = 1
})
