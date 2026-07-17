import { afterEach, describe, expect, mock, test } from 'bun:test'
import server from '../src/index'

describe('native Atlassian token exchange', () => {
  const originalFetch = globalThis.fetch
  const originalClientID = process.env.ATLASSIAN_CLIENT_ID
  const originalClientSecret = process.env.ATLASSIAN_CLIENT_SECRET

  afterEach(() => {
    globalThis.fetch = originalFetch
    if (originalClientID === undefined) delete process.env.ATLASSIAN_CLIENT_ID
    else process.env.ATLASSIAN_CLIENT_ID = originalClientID
    if (originalClientSecret === undefined) delete process.env.ATLASSIAN_CLIENT_SECRET
    else process.env.ATLASSIAN_CLIENT_SECRET = originalClientSecret
  })

  test('sends the Atlassian audience when exchanging an authorization code', async () => {
    process.env.ATLASSIAN_CLIENT_ID = 'client-id'
    process.env.ATLASSIAN_CLIENT_SECRET = 'client-secret'
    let tokenPayload: Record<string, unknown> | undefined

    globalThis.fetch = mock(async (_url, init) => {
      tokenPayload = JSON.parse(String(init?.body))
      return new Response(
        JSON.stringify({
          error: 'invalid_grant',
          error_description: 'authorization code has mismatched aud'
        }),
        { status: 400 }
      )
    }) as typeof fetch

    await server.fetch(
      new Request('http://localhost/api/auth/native/exchange', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ code: 'code', redirect_uri: 'balm://auth/callback' })
      })
    )

    expect(tokenPayload).toMatchObject({
      grant_type: 'authorization_code',
      client_id: 'client-id',
      client_secret: 'client-secret',
      code: 'code',
      redirect_uri: 'balm://auth/callback',
      audience: 'api.atlassian.com'
    })
    expect(tokenPayload).not.toHaveProperty('code_verifier')
  })
})
