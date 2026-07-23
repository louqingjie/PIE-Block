/**
 * Diagnose bundled UV4 batch build (why 0xC0000135 / missing log).
 */
import fs from 'node:fs';
import path from 'node:path';
import { spawn, execFile } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { promisify } from 'node:util';

const execFileAsync = promisify(execFile);
const root = path.join(path.dirname(fileURLToPath(import.meta.url)), '..');
const projectRoot = path.join(root, 'stc32g', 'Projects', '0000.培训模板');
const uvproj = path.join(projectRoot, 'MDK', 'Project_Template.uvproj');
const logPath = path.join(projectRoot, 'MDK', 'diag_build.log');

const candidates = [
    {
        name: 'bundled',
        uv4: path.join(root, 'vendor', 'keil-toolchain', 'UV4', 'UV4.exe'),
        keilRoot: path.join(root, 'vendor', 'keil-toolchain'),
    },
    {
        name: 'system',
        uv4: path.join(process.env.LOCALAPPDATA || '', 'Keil_v5', 'UV4', 'UV4.exe'),
        keilRoot: path.join(process.env.LOCALAPPDATA || '', 'Keil_v5'),
    },
];

function ensureToolsIni(keilRoot) {
    const iniPath = path.join(keilRoot, 'TOOLS.INI');
    if (!fs.existsSync(iniPath)) return;
    let raw = fs.readFileSync(iniPath, 'utf8');
    const rootSlash = keilRoot.endsWith('\\') ? keilRoot : `${keilRoot}\\`;
    const c251Slash = path.join(keilRoot, 'C251') + '\\';
    raw = raw.replace(/\{\{KEIL_ROOT\}\}/g, keilRoot);
    const rewrite = (text, section, value) => {
        const secRe = new RegExp(`(\\[${section}\\][\\s\\S]*?)(?=\\n\\[|$)`, 'i');
        if (!secRe.test(text)) return `${text.trimEnd()}\r\n[${section}]\r\nPATH="${value}"\r\n`;
        return text.replace(secRe, (block) => {
            if (/^\s*PATH\s*=/im.test(block)) {
                return block.replace(/^\s*PATH\s*=.*$/im, `PATH="${value}"`);
            }
            return block.replace(new RegExp(`\\[${section}\\]`, 'i'), `[${section}]\r\nPATH="${value}"`);
        });
    };
    raw = rewrite(raw, 'C251', c251Slash);
    raw = rewrite(raw, 'UV2', rootSlash);
    try {
        fs.writeFileSync(iniPath, raw.endsWith('\n') ? raw : `${raw}\r\n`, 'utf8');
        console.log(`[${path.basename(keilRoot)}] TOOLS.INI updated`);
    } catch (e) {
        console.log('TOOLS.INI write failed', e.message);
    }
}

function run(name, uv4, keilRoot, cwd) {
    return new Promise((resolve) => {
        if (fs.existsSync(logPath)) fs.unlinkSync(logPath);
        console.log(`\n=== ${name} cwd=${cwd} ===`);
        console.log('uv4 exists', fs.existsSync(uv4), uv4);
        const child = spawn(uv4, ['-b', uvproj, '-o', logPath], {
            cwd,
            windowsHide: true,
            stdio: ['ignore', 'pipe', 'pipe'],
            env: { ...process.env, KEIL_ROOT: keilRoot, UV2_ROOT: keilRoot },
        });
        let out = '';
        let err = '';
        child.stdout?.on('data', (d) => {
            out += d.toString();
        });
        child.stderr?.on('data', (d) => {
            err += d.toString();
        });
        const t = setTimeout(() => {
            child.kill();
            resolve({ name, timedOut: true });
        }, 60000);
        child.on('error', (e) => {
            clearTimeout(t);
            console.log('spawn error', e.message);
            resolve({ name, spawnError: e.message });
        });
        child.on('close', (code, signal) => {
            clearTimeout(t);
            const log = fs.existsSync(logPath) ? fs.readFileSync(logPath, 'utf8') : '';
            console.log('exit', code, 'signal', signal);
            console.log('stdout', out.slice(0, 200));
            console.log('stderr', err.slice(0, 200));
            console.log('log exists', fs.existsSync(logPath), 'len', log.length);
            if (log) console.log(log.split(/\r?\n/).slice(-12).join('\n'));
            resolve({ name, code, logLen: log.length });
        });
    });
}

// PE import via powershell [optional]
async function listImports(exe) {
    try {
        const { stdout } = await execFileAsync(
            'powershell',
            [
                '-NoProfile',
                '-Command',
                `$bytes=[IO.File]::ReadAllBytes('${exe.replace(/'/g, "''")}'); 'size='+$bytes.Length`,
            ],
            { windowsHide: true, timeout: 10000 },
        );
        console.log(stdout.trim());
    } catch {
        /* ignore */
    }
}

for (const c of candidates) {
    if (!fs.existsSync(c.uv4)) {
        console.log('skip missing', c.name);
        continue;
    }
    if (c.name === 'bundled') ensureToolsIni(c.keilRoot);
    await listImports(c.uv4);
    await run(c.name, c.uv4, c.keilRoot, path.dirname(uvproj));
    await run(`${c.name}-uv4cwd`, c.uv4, c.keilRoot, path.dirname(c.uv4));
}
