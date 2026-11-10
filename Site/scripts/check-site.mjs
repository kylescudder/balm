import assert from 'node:assert/strict'
import { existsSync, readFileSync } from 'node:fs'
import { join } from 'node:path'

const root = 'dist'
for (const [path, expected] of [
  ['index.html', '<title>Balm - a native, keyboard-driven Jira client</title>'],
  ['privacy/index.html', '<title>Privacy Policy - Balm</title>'],
  ['terms/index.html', '<title>Terms of Use - Balm</title>'],
  ['support/index.html', '<title>Support - Balm</title>']
]) {
  const html = readFileSync(join(root, path), 'utf8')
  assert(html.includes(expected), `Missing content: ${path}`)
  const assets = [
    ...html.matchAll(/(?:src|href)="(\/(?:_astro|assets)\/[^"?#]+)"/g)
  ]
  assert(
    assets.some(([, asset]) => asset.startsWith('/_astro/')),
    `Missing built assets: ${path}`
  )
  for (const [, asset] of assets) {
    assert(existsSync(join(root, asset)), `Missing asset: ${asset}`)
  }
}
assert(
  readFileSync(join(root, 'privacy/index.html'), 'utf8').includes(
    'auth.getbalm.app'
  ),
  'The privacy policy must name the auth service'
)
console.log('Home, legal and support pages and built assets verified.')
