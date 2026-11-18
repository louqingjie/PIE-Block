/**
 * Offline smoke test for the discovery/renewal cycle, with no DSH running.
 *
 *   node tool/smoke.mjs
 *
 * It exercises the same decisions the Host would drive: register on a live
 * discovery file, rebuild on a token or pid change, withdraw when the app
 * stops, ignore a stale pid and a non-loopback endpoint, and clean up on
 * plugin disposal.
 */

import assert from 'node:assert/strict'
import { mkdtempSync, rmSync, unlinkSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'

import { apply } from '../index.js'

const directory = mkdtempSync(join(tmpdir(), 'pieblock-dsh-mcp-'))
const bridgePath = join(directory, 'mcp-bridge.json')

const registrations = []
let active = 0
let effectCleanup

const ctx = {
  mcpManager: {
    register(serverName, entry) {
      registrations.push({ serverName, entry })
      active += 1
      return () => {
        active -= 1
      }
    },
  },
  effect(callback) {
    effectCleanup = callback()
    return { dispose: effectCleanup }
  },
  logger: () => ({ info() {}, warn() {}, error() {} }),
}

const writeBridge = (patch = {}) => writeFileSync(bridgePath, JSON.stringify({
  schema: 1,
  app: 'pieblock',
  path: '/mcp',
  port: 47173,
  endpoint: 'http://127.0.0.1:47173/mcp',
  token: 'token-a',
  pid: process.pid,
  startedAt: '2026-11-18T10:00:00.000',
  ...patch,
}))

const waitFor = async (predicate, label) => {
  const deadline = Date.now() + 3000
  while (!predicate()) {
    if (Date.now() > deadline) throw new Error(`timed out waiting for ${label}`)
    await new Promise(resolve => setTimeout(resolve, 10))
  }
}

try {
  writeBridge()
  apply(ctx, { bridgePath, pollMs: 60, serverName: 'pieblock' })

  assert.equal(registrations.length, 1, 'the discovery file registers the server immediately')
  assert.equal(registrations[0].serverName, 'pieblock')
  assert.equal(registrations[0].entry.transport, 'streamable-http')
  assert.equal(registrations[0].entry.url, 'http://127.0.0.1:47173/mcp')
  assert.equal(registrations[0].entry.headers.Authorization, 'Bearer token-a')
  assert.equal(active, 1)

  writeBridge({ token: 'token-b', startedAt: '2026-11-18T11:00:00.000' })
  await waitFor(() => registrations.length === 2, 'a rotated token to rebuild the registration')
  assert.equal(registrations[1].entry.headers.Authorization, 'Bearer token-b')
  assert.equal(active, 1, 'the replaced registration was withdrawn')

  writeBridge({ pid: 999_999 })
  await waitFor(() => active === 0, 'a stale pid to withdraw the registration')
  await new Promise(resolve => setTimeout(resolve, 60))
  assert.equal(registrations.length, 2, 'a dead pid never registers')

  writeBridge({ endpoint: 'http://192.0.2.10:47173/mcp' })
  await new Promise(resolve => setTimeout(resolve, 60))
  assert.equal(registrations.length, 2, 'a non-loopback endpoint is rejected')
  assert.equal(active, 0)

  writeBridge()
  await waitFor(() => active === 1, 'the app to come back')

  unlinkSync(bridgePath)
  await waitFor(() => active === 0, 'the app to stop')
  assert.equal(registrations.length, 3, 'stopping does not register again')

  writeBridge()
  await waitFor(() => active === 1, 'a restart')
  effectCleanup?.()
  assert.equal(active, 0, 'plugin disposal withdraws the registration')

  console.log('smoke passed')
} finally {
  rmSync(directory, { recursive: true, force: true })
}
