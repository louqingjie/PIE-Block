/**
 * PIE-Block MCP bridge for DeepSeek Harness.
 *
 * PIE-Block's desktop app already ships an MCP server: six project tools behind
 * a loopback Streamable HTTP endpoint, authorized by a per-installation token.
 * Its `AI 接入（MCP）` switch decides whether that server exists. Copying the
 * endpoint and token into every client is the friction this plugin removes:
 * while the app runs, the plugin registers the server with `ctx.mcpManager`;
 * when the app stops or the switch turns off, the registration is withdrawn and
 * the `mcp__pieblock__*` tools disappear.
 *
 * The plugin is a configuration-free bundle. It reads the app's discovery file,
 * never writes PIE-Block's files or settings, and never starts the app.
 */

import { isProcessAlive, readBridgeFile, resolveBridgePaths } from './bridge.js'

/** Plugin name used in Loader diagnostics and log lines. */
export const name = 'pieblock-mcp'

/** The MCP manager owns the server fleet; without it this plugin stays inactive. */
export const inject = ['mcpManager']

const DEFAULT_SERVER_NAME = 'pieblock'
const DEFAULT_POLL_MS = 2000
const DEFAULT_STARTUP_TIMEOUT_MS = 8000

/**
 * Register and withdraw the PIE-Block server as the app starts and stops.
 *
 * @param {import('@deepseek-ai/cordis').Context} ctx - plugin context.
 * @param {{bridgePath?: string, pollMs?: number, serverName?: string, startupTimeoutMs?: number}} [config]
 */
export function apply(ctx, config) {
  const options = resolveOptions(config)

  let timer
  let registered
  let failedSignature = ''
  let disposed = false

  const log = (level, message) => {
    try {
      // Cordis exposes a logger service; accept both the service-shaped and
      // factory-shaped accessors so a missing one only costs log formatting.
      const sink = typeof ctx.logger === 'function' ? ctx.logger(name) : ctx.logger
      const write = sink?.[level]
      if (typeof write === 'function') {
        write.call(sink, message)
        return
      }
    } catch {
      // A missing logger service must not break discovery.
    }
    const line = `[${name}] ${message}`
    if (level === 'warn') console.warn(line)
    else if (level === 'error') console.error(line)
    else console.log(line)
  }

  const withdraw = () => {
    const current = registered
    registered = undefined
    if (current === undefined) return
    try {
      current.dispose()
    } catch {
      // The manager may already have disposed the instance.
    }
  }

  const tick = async () => {
    if (disposed) return

    const bridge = readBridgeFile(options.paths)
    if (bridge === undefined || (bridge.pid !== undefined && !isProcessAlive(bridge.pid))) {
      // No switch, no app, or a discovery file left behind by a crash.
      withdraw()
      failedSignature = ''
      return
    }

    const signature = [bridge.endpoint, bridge.token, bridge.pid ?? '', bridge.startedAt ?? ''].join('\n')
    if (registered?.signature === signature || failedSignature === signature) return

    // A changed endpoint, token, pid, or start time means a new server instance.
    withdraw()
    try {
      const dispose = ctx.mcpManager.register(options.serverName, {
        transport: 'streamable-http',
        url: bridge.endpoint,
        headers: { Authorization: `Bearer ${bridge.token}` },
        startupTimeoutMs: options.startupTimeoutMs,
      })
      registered = { signature, dispose }
      failedSignature = ''
      log('info', `registered ${options.serverName} at ${bridge.endpoint}`)
    } catch (error) {
      // A name already configured in Settings is a user decision; retrying the
      // same document every two seconds would only flood the log.
      failedSignature = signature
      log('warn', `cannot register ${options.serverName}: ${error?.message ?? error}`)
    }
  }

  ctx.effect(() => {
    timer = setInterval(() => {
      void tick()
    }, options.pollMs)
    // A watcher must not be the reason the Host stays alive.
    timer.unref?.()
    void tick()

    return () => {
      disposed = true
      clearInterval(timer)
      withdraw()
    }
  })
}

/**
 * Resolve the row configuration, accepting the string-valued numbers YAML may
 * carry when a user edits the patch by hand.
 *
 * @param {Record<string, unknown> | undefined} config - row configuration.
 */
function resolveOptions(config) {
  const raw = config ?? {}
  const number = (value, fallback, minimum) => {
    const parsed = typeof value === 'string' ? Number(value) : value
    return typeof parsed === 'number' && Number.isFinite(parsed) && parsed >= minimum ? parsed : fallback
  }
  const text = (value) => (typeof value === 'string' && value.trim() !== '' ? value.trim() : undefined)

  const bridgePath = text(raw.bridgePath)
  return {
    paths: bridgePath === undefined ? resolveBridgePaths() : [bridgePath],
    pollMs: number(raw.pollMs, DEFAULT_POLL_MS, 50),
    serverName: text(raw.serverName) ?? DEFAULT_SERVER_NAME,
    startupTimeoutMs: number(raw.startupTimeoutMs, DEFAULT_STARTUP_TIMEOUT_MS, 1),
  }
}
