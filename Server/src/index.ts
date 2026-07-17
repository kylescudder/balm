import { Hono } from 'hono'
import { cors } from 'hono/cors'

const ATLASSIAN_TOKEN_URL = 'https://auth.atlassian.com/oauth/token'
const ATLASSIAN_RESOURCES_URL =
  'https://api.atlassian.com/oauth/token/accessible-resources'

type TokenJson = {
  access_token: string
  refresh_token?: string
  expires_in?: number
  scope?: string
  token_type?: string
}

type Resource = {
  id: string
  name: string
  url: string
  scopes: string[]
}

const requireSecrets = (): { clientId: string; clientSecret: string } | Response => {
  const clientId = process.env.ATLASSIAN_CLIENT_ID
  const clientSecret = process.env.ATLASSIAN_CLIENT_SECRET
  if (!clientId || !clientSecret) {
    return Response.json(
      { error: 'ATLASSIAN_CLIENT_ID / ATLASSIAN_CLIENT_SECRET not configured' },
      { status: 500 }
    )
  }
  return { clientId, clientSecret }
}

const app = new Hono()

app.use('*', cors())

app.get('/health', (c) => c.json({ ok: true }))

/**
 * Native client token exchange. Atlassian's /oauth/token requires client_secret
 * so the secret stays here. The native app posts { code, redirect_uri } and
 * gets a token bundle plus the resolved Jira site identity in one round-trip.
 */
app.post('/api/auth/native/exchange', async (c) => {
  const secrets = requireSecrets()
  if (secrets instanceof Response) return secrets

  let body: { code?: string; redirect_uri?: string }
  try {
    body = await c.req.json()
  } catch {
    return c.json({ error: 'Invalid JSON body' }, 400)
  }
  const { code, redirect_uri } = body
  if (!code || !redirect_uri) {
    return c.json(
      { error: 'Missing one of: code, redirect_uri' },
      400
    )
  }

  const tokenRes = await fetch(ATLASSIAN_TOKEN_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      grant_type: 'authorization_code',
      client_id: secrets.clientId,
      client_secret: secrets.clientSecret,
      code,
      redirect_uri
    })
  })
  if (!tokenRes.ok) {
    return c.json(
      { error: 'Token exchange failed', details: await tokenRes.text() },
      tokenRes.status as never
    )
  }
  const tokenJson = (await tokenRes.json()) as TokenJson

  const resourcesRes = await fetch(ATLASSIAN_RESOURCES_URL, {
    headers: { Authorization: `Bearer ${tokenJson.access_token}` }
  })
  if (!resourcesRes.ok) {
    return c.json(
      {
        error: 'Failed to fetch accessible resources',
        details: await resourcesRes.text()
      },
      resourcesRes.status as never
    )
  }
  const resources = (await resourcesRes.json()) as Resource[]
  if (!Array.isArray(resources) || resources.length === 0) {
    return c.json({ error: 'No accessible Jira resources for this account' }, 400)
  }
  const first = resources[0]!

  return c.json({
    access_token: tokenJson.access_token,
    refresh_token: tokenJson.refresh_token ?? null,
    expires_in: tokenJson.expires_in ?? 3600,
    scope: tokenJson.scope ?? null,
    token_type: tokenJson.token_type ?? 'Bearer',
    cloud_id: first.id,
    site_name: first.name,
    site_url: first.url,
    scopes: first.scopes,
    resources
  })
})

/**
 * Native client token refresh. Same secret reason as /exchange.
 */
app.post('/api/auth/native/refresh', async (c) => {
  const secrets = requireSecrets()
  if (secrets instanceof Response) return secrets

  let body: { refresh_token?: string }
  try {
    body = await c.req.json()
  } catch {
    return c.json({ error: 'Invalid JSON body' }, 400)
  }
  const { refresh_token } = body
  if (!refresh_token) {
    return c.json({ error: 'Missing refresh_token' }, 400)
  }

  const tokenRes = await fetch(ATLASSIAN_TOKEN_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      grant_type: 'refresh_token',
      client_id: secrets.clientId,
      client_secret: secrets.clientSecret,
      refresh_token
    })
  })
  if (!tokenRes.ok) {
    return c.json(
      { error: 'Token refresh failed', details: await tokenRes.text() },
      tokenRes.status as never
    )
  }
  const tokenJson = (await tokenRes.json()) as TokenJson

  return c.json({
    access_token: tokenJson.access_token,
    refresh_token: tokenJson.refresh_token ?? null,
    expires_in: tokenJson.expires_in ?? 3600,
    scope: tokenJson.scope ?? null,
    token_type: tokenJson.token_type ?? 'Bearer'
  })
})

const port = Number(process.env.PORT ?? 3000)
console.log(`Balm BFF listening on http://localhost:${port}`)

export default {
  port,
  fetch: app.fetch
}
