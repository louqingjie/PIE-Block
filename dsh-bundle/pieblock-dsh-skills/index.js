/**
 * PIE-Block DSH plugin: register the packaged skills into the host skill registry.
 *
 * The two skill bodies and their referenced assets live under `skills/`. They are
 * registered with `ctx.skills.register(...)` during plugin activation, which files
 * them into the global registry layer: every session sees them regardless of the
 * working directory or agent preset. No files are written to `~/.dsh/skills`, and
 * disposal unregisters both skills.
 *
 * @module pieblock-dsh-skills
 */

import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

export const name = 'pieblock-skills'
export const inject = ['skills']

const packageRoot = dirname(fileURLToPath(import.meta.url))

/** Packaged skills, in catalog order. */
const SKILLS = [
  { name: 'pieblock-config', directory: 'pieblock-config' },
  { name: 'pieblock-troubleshooting', directory: 'pieblock-troubleshooting' },
]

/**
 * Split one packaged SKILL.md into its frontmatter fields and Markdown body.
 * Only `name`/`description`/`whenToUse` matter here; the pack ships only the
 * simple single-line YAML frontmatter this plugin author controls.
 * @param {string} filePath absolute SKILL.md path.
 * @returns {{ description: string, whenToUse: string | undefined, content: string }}
 */
function parseSkillFile(filePath) {
  const raw = readFileSync(filePath, 'utf8').replace(/^\uFEFF/, '')
  const match = /^---\r?\n([\s\S]*?)\r?\n---\r?\n?/.exec(raw)
  if (match === null) {
    throw new Error(`pieblock-skills: ${filePath} is missing YAML frontmatter`)
  }
  const fields = new Map()
  for (const line of match[1].split(/\r?\n/)) {
    const separator = line.indexOf(':')
    if (separator <= 0) continue
    fields.set(line.slice(0, separator).trim(), line.slice(separator + 1).trim())
  }
  const description = fields.get('description')
  if (description === undefined || description.length === 0) {
    throw new Error(`pieblock-skills: ${filePath} has no description`)
  }
  return {
    description,
    whenToUse: fields.get('whenToUse'),
    content: raw.slice(match[0].length).trim(),
  }
}

/**
 * Register both packaged skills for the running DSH host.
 * @param {import('@deepseek-ai/cordis').Context} ctx host plugin context.
 */
export function apply(ctx) {
  for (const entry of SKILLS) {
    const directory = join(packageRoot, 'skills', entry.directory)
    const path = join(directory, 'SKILL.md')
    const { description, whenToUse, content } = parseSkillFile(path)
    ctx.skills.register({
      name: entry.name,
      description,
      ...whenToUse === undefined ? {} : { whenToUse },
      source: 'runtime',
      path,
      resourceBase: { kind: 'directory', path: directory },
      content,
    })
  }
}
