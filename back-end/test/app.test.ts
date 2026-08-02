import request from 'supertest'
import { describe, expect, it } from 'vitest'

import { createApp } from '../src/app.js'
import { readServerConfig } from '../src/server-config.js'

describe('API security contract', () => {
  it('serves a minimal, uncached health response with security headers', async () => {
    const response = await request(createApp()).get('/api/health').expect(200)

    expect(response.body).toEqual({ ok: true })
    expect(response.headers['cache-control']).toBe('no-store')
    expect(response.headers['x-content-type-options']).toBe('nosniff')
    expect(response.headers['x-frame-options']).toBe('DENY')
    expect(response.headers['x-powered-by']).toBeUndefined()
  })

  it('does not grant cross-origin access from an arbitrary origin', async () => {
    const response = await request(createApp())
      .get('/api/health')
      .set('Origin', 'https://attacker.example')
      .expect(200)

    expect(response.headers['access-control-allow-origin']).toBeUndefined()
    expect(response.headers['access-control-allow-credentials']).toBeUndefined()
  })

  it('allows only read-only API methods', async () => {
    const response = await request(createApp()).post('/api/health').send({ value: true }).expect(405)

    expect(response.body).toEqual({ error: 'method_not_allowed' })
    expect(response.headers.allow).toBe('GET, HEAD, OPTIONS')
  })

  it('answers preflight-like requests without granting CORS access', async () => {
    const response = await request(createApp()).options('/api/health').expect(204)

    expect(response.headers.allow).toBe('GET, HEAD, OPTIONS')
    expect(response.headers['access-control-allow-origin']).toBeUndefined()
  })

  it('does not expose the former mutable page-view endpoint', async () => {
    await request(createApp()).get('/api/pageview').expect(404, { error: 'not_found' })
  })

  it('returns JSON 404 responses outside the API', async () => {
    await request(createApp()).get('/missing').expect(404, { error: 'not_found' })
  })

  it('rejects unsafe proxy-hop configuration', () => {
    expect(() => createApp({ trustProxyHops: -1 })).toThrow(RangeError)
    expect(() => createApp({ trustProxyHops: 3 })).toThrow(RangeError)
  })

  it('keeps the standalone API on loopback and bounds listener settings', () => {
    expect(readServerConfig({})).toEqual({ host: '127.0.0.1', port: 3006, trustProxyHops: 0 })
    expect(readServerConfig({ HOST: '::1', PORT: '3007', TRUST_PROXY_HOPS: '1' })).toEqual({
      host: '::1',
      port: 3007,
      trustProxyHops: 1,
    })
    expect(() => readServerConfig({ HOST: '0.0.0.0' })).toThrow(RangeError)
    expect(() => readServerConfig({ PORT: '0' })).toThrow(RangeError)
    expect(() => readServerConfig({ TRUST_PROXY_HOPS: '3' })).toThrow(RangeError)
  })
})
