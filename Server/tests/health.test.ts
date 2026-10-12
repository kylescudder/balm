import { afterEach, expect, test } from 'bun:test'
import server from '../src/index'
const original = { ...process.env }
afterEach(() => {
  for (const key of ['ATLASSIAN_CLIENT_ID', 'ATLASSIAN_CLIENT_SECRET', 'BALM_AUTH_REVISION']) {
    if (original[key] === undefined) delete process.env[key]
    else process.env[key] = original[key]
  }
})
test('readiness rejects absent credentials without revealing their values', async () => {
  delete process.env.ATLASSIAN_CLIENT_SECRET
  const response = await server.fetch(new Request('http://localhost/health'))
  expect(response.status).toBe(503)
  expect(await response.json()).toEqual({ ok: false })
})
test('ready service exposes its revision and disables caching', async () => {
  process.env.ATLASSIAN_CLIENT_ID = 'test-id'
  process.env.ATLASSIAN_CLIENT_SECRET = 'test-secret'
  process.env.BALM_AUTH_REVISION = 'a'.repeat(40)
  const response = await server.fetch(new Request('http://localhost/health'))
  expect(response.status).toBe(200)
  expect(response.headers.get('X-Balm-Auth-Revision')).toBe('a'.repeat(40))
  expect(response.headers.get('Cache-Control')).toBe('no-store')
  expect(await response.json()).toEqual({ ok: true })
})
