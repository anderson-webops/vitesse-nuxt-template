#!/usr/bin/env node
import { access, readFile } from 'node:fs/promises'
import { resolve } from 'node:path'

const projectRoot = resolve(import.meta.dirname, '..')
const paths = {
  apiApp: resolve(projectRoot, 'back-end/dist/app.js'),
  apiServer: resolve(projectRoot, 'back-end/dist/server.js'),
  frontendHealth: resolve(projectRoot, 'front-end/.output/public/healthz'),
  frontendIndex: resolve(projectRoot, 'front-end/.output/public/index.html'),
  netlifyFunction: resolve(projectRoot, 'netlify/functions/api.ts'),
}

for (const path of Object.values(paths))
  await access(path)

const [apiApp, apiServer, frontendHealth, frontendIndex] = await Promise.all([
  readFile(paths.apiApp, 'utf8'),
  readFile(paths.apiServer, 'utf8'),
  readFile(paths.frontendHealth, 'utf8'),
  readFile(paths.frontendIndex, 'utf8'),
])

function assert(condition, message) {
  if (!condition)
    throw new Error(message)
}

assert(JSON.parse(frontendHealth).ok === true, 'Static health check must return {"ok":true}')
assert(/http-equiv=["']content-security-policy["']/i.test(frontendIndex), 'Generated HTML must include a CSP meta policy')
assert(!frontendIndex.includes('http://localhost:3006'), 'Generated HTML must not embed the local API origin')
assert(!frontendIndex.includes('/api/pageview'), 'Generated HTML must not reference the removed mutable endpoint')
assert(!apiApp.includes('startedAt') && !apiApp.includes('pageview'), 'Compiled API must not expose process timing or page-view state')
assert(!apiApp.includes('sourceMappingURL') && !apiServer.includes('sourceMappingURL'), 'Production API output must not expose source maps')

console.log('Deployment output check passed for the static frontend, Express API, and Netlify function.')
