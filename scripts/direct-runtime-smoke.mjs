#!/usr/bin/env node
import assert from 'node:assert/strict'
import { spawn } from 'node:child_process'
import net from 'node:net'
import path from 'node:path'
import process from 'node:process'

const repositoryRoot = path.resolve(import.meta.dirname, '..')

async function reservePort() {
  const server = net.createServer()
  await new Promise((resolveListen, reject) => {
    server.once('error', reject)
    server.listen(0, '127.0.0.1', resolveListen)
  })
  const address = server.address()
  assert.ok(address && typeof address === 'object')
  await new Promise((resolveClose, reject) => server.close(error => error ? reject(error) : resolveClose()))
  return address.port
}

function isRunning(child) {
  return child.exitCode === null && child.signalCode === null
}

async function stopProcessTree(child) {
  if (!child.pid || !isRunning(child))
    return
  const target = process.platform === 'win32' ? child.pid : -child.pid
  try {
    process.kill(target, 'SIGTERM')
  }
  catch (error) {
    if (error?.code !== 'ESRCH')
      throw error
    return
  }
  await Promise.race([
    new Promise(resolveExit => child.once('exit', resolveExit)),
    new Promise(resolveWait => setTimeout(resolveWait, 5_000)),
  ])
  if (isRunning(child))
    process.kill(target, 'SIGKILL')
}

async function waitForHealth(baseUrl, child, diagnostics) {
  const deadline = Date.now() + 20_000
  let lastError
  while (Date.now() < deadline) {
    if (!isRunning(child))
      throw new Error(`Direct API exited before health: ${diagnostics()}`)
    try {
      const response = await fetch(`${baseUrl}/api/health`, { signal: AbortSignal.timeout(2_000) })
      if (response.ok)
        return
      lastError = new Error(`/api/health returned ${response.status}`)
    }
    catch (error) {
      lastError = error
    }
    await new Promise(resolveWait => setTimeout(resolveWait, 250))
  }
  throw new Error(`Direct API did not become healthy: ${lastError?.message || 'unknown error'}; ${diagnostics()}`)
}

const port = await reservePort()
const baseUrl = `http://127.0.0.1:${port}`
let diagnosticOutput = ''
const child = spawn(process.execPath, ['back-end/dist/server.js'], {
  cwd: repositoryRoot,
  detached: process.platform !== 'win32',
  env: {
    ...process.env,
    HOST: '127.0.0.1',
    NODE_ENV: 'production',
    PORT: String(port),
    TRUST_PROXY_HOPS: '1',
  },
  stdio: ['ignore', 'pipe', 'pipe'],
})
for (const stream of [child.stdout, child.stderr]) {
  stream.on('data', (data) => {
    diagnosticOutput = `${diagnosticOutput}${data.toString()}`.slice(-4_000)
  })
}

try {
  await waitForHealth(baseUrl, child, () => diagnosticOutput.trim())

  const health = await fetch(`${baseUrl}/api/health`, { signal: AbortSignal.timeout(5_000) })
  assert.equal(health.status, 200)
  assert.deepEqual(await health.json(), { ok: true })
  assert.equal(health.headers.get('cache-control'), 'no-store')
  assert.equal(health.headers.get('x-content-type-options'), 'nosniff')
  assert.equal(health.headers.get('x-frame-options'), 'DENY')
  assert.equal(health.headers.get('x-powered-by'), null)

  const mutation = await fetch(`${baseUrl}/api/health`, {
    body: '{}',
    headers: { 'content-type': 'application/json' },
    method: 'POST',
    signal: AbortSignal.timeout(5_000),
  })
  assert.equal(mutation.status, 405)
  assert.deepEqual(await mutation.json(), { error: 'method_not_allowed' })

  const reserved = await fetch(`${baseUrl}/admin`, { signal: AbortSignal.timeout(5_000) })
  assert.equal(reserved.status, 404)
  assert.deepEqual(await reserved.json(), { error: 'not_found' })

  console.log(JSON.stringify({ directRuntime: 'passed', loopback: true, mutations: 'denied' }))
}
finally {
  await stopProcessTree(child)
}
