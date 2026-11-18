/**
 * Locate and read PIE-Block's runtime discovery file.
 *
 * The desktop app writes `mcp-bridge.json` next to its application-support
 * data while the "AI 接入（MCP）" switch is on, and deletes it on stop. The file
 * carries the loopback endpoint and the per-installation token, so a client
 * never needs a hand-copied secret; the token itself is never logged here.
 *
 * This module has no Cordis dependency so the discovery rules stay testable
 * with plain Node.
 */

import { readFileSync } from 'node:fs'
import { homedir } from 'node:os'
import { join } from 'node:path'

/** File name written by `McpHttpServer.start({ bridgeFile })`. */
export const BRIDGE_FILE = 'mcp-bridge.json'

/** Application-support directory segments created by Flutter's path_provider. */
const ORG_SEGMENT = 'com.wpie'
const APP_SEGMENT = 'PIE-Block'

/**
 * Candidate discovery files, most specific first.
 *
 * `PIEBLOCK_MCP_BRIDGE` overrides everything, which is how a portable or
 * relocated installation points the plugin at its own file.
 *
 * @param {NodeJS.ProcessEnv} [env] - environment to read (defaults to `process.env`).
 * @param {string} [platform] - `process.platform` value to use.
 * @param {string} [home] - home directory to use.
 * @returns {string[]} absolute candidate paths.
 */
export function resolveBridgePaths(env = process.env, platform = process.platform, home = homedir()) {
  const override = env.PIEBLOCK_MCP_BRIDGE
  if (typeof override === 'string' && override.trim() !== '') return [override.trim()]

  if (platform === 'win32') {
    const appData = env.APPDATA ?? join(home, 'AppData', 'Roaming')
    return [
      join(appData, ORG_SEGMENT, APP_SEGMENT, BRIDGE_FILE),
      join(appData, APP_SEGMENT, BRIDGE_FILE),
    ]
  }
  if (platform === 'darwin') {
    const support = join(home, 'Library', 'Application Support')
    return [
      join(support, ORG_SEGMENT, APP_SEGMENT, BRIDGE_FILE),
      join(support, `${ORG_SEGMENT}.${APP_SEGMENT}`, BRIDGE_FILE),
      join(support, APP_SEGMENT, BRIDGE_FILE),
    ]
  }
  const data = env.XDG_DATA_HOME ?? join(home, '.local', 'share')
  return [
    join(data, ORG_SEGMENT, APP_SEGMENT, BRIDGE_FILE),
    join(data, APP_SEGMENT, BRIDGE_FILE),
  ]
}

/**
 * Read the first candidate that parses into a usable bridge description.
 *
 * A file being rewritten, a malformed document, and a missing file all read as
 * "not running" so a half-written discovery file can never produce a server.
 *
 * @param {string[]} paths - candidate paths in priority order.
 * @returns {{endpoint: string, token: string, pid?: number, startedAt?: string} | undefined}
 */
export function readBridgeFile(paths) {
  for (const path of paths) {
    let parsed
    try {
      parsed = JSON.parse(readFileSync(path, 'utf8'))
    } catch {
      continue
    }
    const bridge = normalizeBridge(parsed)
    if (bridge !== undefined) return bridge
  }
  return undefined
}

/**
 * Validate one decoded discovery document.
 *
 * Only a loopback `http:` endpoint is accepted: the token is handed to whatever
 * host the file names, so a rewritten file must not be able to forward it to a
 * remote service.
 *
 * @param {unknown} value - decoded JSON value.
 * @returns {{endpoint: string, token: string, pid?: number, startedAt?: string} | undefined}
 */
export function normalizeBridge(value) {
  if (value === null || typeof value !== 'object') return undefined
  const record = /** @type {Record<string, unknown>} */ (value)

  if (record.schema !== undefined && record.schema !== 1) return undefined
  if (record.app !== undefined && record.app !== 'pieblock') return undefined

  const endpoint = typeof record.endpoint === 'string' ? record.endpoint : undefined
  const token = typeof record.token === 'string' && record.token !== '' ? record.token : undefined
  if (endpoint === undefined || token === undefined) return undefined

  let url
  try {
    url = new URL(endpoint)
  } catch {
    return undefined
  }
  if (url.protocol !== 'http:') return undefined
  if (url.hostname !== '127.0.0.1' && url.hostname !== 'localhost' && url.hostname !== '[::1]') return undefined

  return {
    endpoint,
    token,
    pid: Number.isInteger(record.pid) ? /** @type {number} */ (record.pid) : undefined,
    startedAt: typeof record.startedAt === 'string' ? record.startedAt : undefined,
  }
}

/**
 * Whether a process id is still alive; an inaccessible process counts as alive.
 *
 * The discovery file records the app's pid, so a stale file left by a crash does
 * not register a server that cannot answer. Pid reuse is possible in theory;
 * the recorded `startedAt` and the connection result cover the remaining risk.
 *
 * @param {number} pid - process id to test.
 * @returns {boolean}
 */
export function isProcessAlive(pid) {
  try {
    process.kill(pid, 0)
    return true
  } catch (error) {
    // EPERM means the process exists but belongs to another user.
    return /** @type {{code?: string}} */ (error)?.code === 'EPERM'
  }
}
