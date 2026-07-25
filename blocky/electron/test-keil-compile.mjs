/**
 * 无界面自检：探测 Keil 并用示例代码批编译。
 *
 * 用法：
 *   node electron/test-keil-compile.mjs
 *   node electron/test-keil-compile.mjs --bundled-only
 */
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import fs from 'node:fs';
import { spawn, execFile } from 'node:child_process';
import { promisify } from 'node:util';

const execFileAsync = promisify(execFile);
const __dirname = path.dirname(fileURLToPath(import.meta.url));
const root = path.join(__dirname, '..');
const bundledOnly = process.argv.includes('--bundled-only');

const projectRoot = path.join(root, 'stc32g', 'Projects', '0000.培训模板');
const uvproj = path.join(projectRoot, 'MDK', 'Project_Template.uvproj');
const mainC = path.join(projectRoot, 'USER', 'src', 'main.c');
const hexPath = path.join(projectRoot, 'MDK', 'Objects', 'Project_Template.hex');
const logPath = path.join(projectRoot, 'MDK', 'pie_block_build.log');
const bundledRoot = path.join(root, 'vendor', 'keil-toolchain');

/**
 * 改写内置 TOOLS.INI：μVision 要求 [C251] 段首项为 PATH=。
 * @param {string} keilRoot
 */
function ensureToolsIni(keilRoot) {
    const iniPath = path.join(keilRoot, 'TOOLS.INI');
    if (!fs.existsSync(iniPath)) return { ok: false, message: `缺少 ${iniPath}` };
    let raw = fs.readFileSync(iniPath, 'utf8');
    if (raw.charCodeAt(0) === 0xfeff) raw = raw.slice(1);

    let c251Slash = path.resolve(path.join(keilRoot, 'C251'));
    if (!c251Slash.endsWith('\\')) c251Slash += '\\';
    const pathLine = `PATH="${c251Slash}"`;

    raw = raw.replace(/\{\{KEIL_ROOT\}\}/g, keilRoot);
    // 仅匹配行首段名，避免注释里的 [C251] 被误改
    const secRe = /^[ \t]*\[C251\][ \t]*\r?\n([\s\S]*?)(?=^[ \t]*\[|\s*$)/im;
    if (secRe.test(raw)) {
        raw = raw.replace(secRe, (_m, body) => {
            const lines = String(body)
                .split(/\r?\n/)
                .filter((l) => l.trim() !== '' && !/^\s*PATH\s*=/i.test(l));
            return `[C251]\r\n${pathLine}\r\n${lines.join('\r\n')}${lines.length ? '\r\n' : ''}`;
        });
    } else {
        raw = `${raw.trimEnd()}\r\n[C251]\r\n${pathLine}\r\n`;
    }

    const out = raw.replace(/\r?\n/g, '\r\n');
    fs.writeFileSync(iniPath, out.endsWith('\r\n') ? out : `${out}\r\n`, 'utf8');
    return { ok: true, iniPath };
}

async function findSystemUv4() {
    const roots = [
        path.join(process.env.LOCALAPPDATA || '', 'Keil_v5'),
        'C:\\Keil_v5',
        'D:\\Keil_v5',
    ];
    try {
        const { stdout } = await execFileAsync(
            'reg',
            ['query', 'HKLM\\SOFTWARE\\WOW6432Node\\Keil\\Products\\C251', '/v', 'Path'],
            { windowsHide: true },
        );
        const m = stdout.match(/Path\s+REG_SZ\s+(.+)/i);
        if (m) roots.unshift(path.dirname(m[1].trim()));
    } catch {
        /* ignore */
    }

    for (const r of roots) {
        const p = path.join(r, 'UV4', 'UV4.exe');
        if (fs.existsSync(p)) return { uv4: p, keilRoot: r, source: 'auto' };
    }
    return null;
}

function findBundledUv4() {
    const uv4 = path.join(bundledRoot, 'UV4', 'UV4.exe');
    const c251 = path.join(bundledRoot, 'C251', 'BIN', 'C251.EXE');
    if (fs.existsSync(uv4) && fs.existsSync(c251)) {
        return { uv4, keilRoot: bundledRoot, source: 'bundled' };
    }
    return null;
}

const SAMPLE = `#include "main.h"

/* ===== 全局变量（自动生成）===== */
/* 无 */

/* ===== 主函数 ===== */
void main(void)
{
    Board_Init();

    /* ===== 初始化区 ===== */
    /* pie-block self-test */

    /* ===== 主循环 ===== */
    while (1)
    {
        /* 无 */
    }
}
`;

const bundled = findBundledUv4();
let selected = null;

if (bundledOnly) {
    selected = bundled;
    if (!selected) {
        console.error('FAIL: --bundled-only 但未找到 vendor/keil-toolchain');
        console.error('请先运行: node scripts/prepare-keil-toolchain.mjs');
        process.exit(1);
    }
} else {
    selected = bundled || (await findSystemUv4());
}

console.log('mode:', bundledOnly ? 'bundled-only' : 'bundled-or-system');
console.log('source:', selected?.source || 'none');
console.log('UV4:', selected?.uv4 || null);
console.log('uvproj exists:', fs.existsSync(uvproj));

if (!selected?.uv4 || !fs.existsSync(uvproj)) {
    console.error('FAIL: tools or project missing');
    process.exit(1);
}

if (selected.source === 'bundled') {
    const ini = ensureToolsIni(selected.keilRoot);
    console.log('TOOLS.INI:', ini.ok ? ini.iniPath : ini.message);
}

fs.writeFileSync(mainC, SAMPLE.replace(/\r?\n/g, '\r\n'), 'utf8');
console.log('Wrote main.c');

if (fs.existsSync(logPath)) fs.unlinkSync(logPath);
if (fs.existsSync(hexPath)) {
    try {
        fs.unlinkSync(hexPath);
    } catch {
        /* ignore */
    }
}

const code = await new Promise((resolve, reject) => {
    const child = spawn(selected.uv4, ['-b', uvproj, '-o', logPath], {
        cwd: path.dirname(uvproj),
        windowsHide: true,
        stdio: 'ignore',
        env: {
            ...process.env,
            KEIL_ROOT: selected.keilRoot || '',
            UV2_ROOT: selected.keilRoot || '',
        },
    });
    const t = setTimeout(() => {
        child.kill();
        reject(new Error('timeout'));
    }, 120000);
    child.on('error', (e) => {
        clearTimeout(t);
        reject(e);
    });
    child.on('close', (c) => {
        clearTimeout(t);
        resolve(c ?? 1);
    });
});

const log = fs.existsSync(logPath) ? fs.readFileSync(logPath, 'utf8') : '';
const ok = /0 Error\(s\)/i.test(log) && fs.existsSync(hexPath);
console.log('exitCode:', code);
console.log('hex:', fs.existsSync(hexPath) ? hexPath : 'MISSING');
console.log('--- log tail ---');
console.log(log.split(/\r?\n/).slice(-15).join('\n'));
console.log(ok ? 'PASS' : 'FAIL');
process.exit(ok ? 0 : 2);
