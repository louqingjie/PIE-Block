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
 * 编译前写绝对 PATH；编译后从 TOOLS.INI.template 恢复占位符。
 * @param {string} keilRoot
 * @param {'runtime'|'portable'} mode
 */
function writeToolsIni(keilRoot, mode) {
    const iniPath = path.join(keilRoot, 'TOOLS.INI');
    const tplPath = path.join(keilRoot, 'TOOLS.INI.template');
    const sourcePath = fs.existsSync(tplPath) ? tplPath : iniPath;
    if (!fs.existsSync(sourcePath)) return { ok: false, message: `缺少 ${sourcePath}` };

    let raw = fs.readFileSync(sourcePath, 'utf8');
    if (raw.charCodeAt(0) === 0xfeff) raw = raw.slice(1);

    if (mode === 'portable') {
        // 始终按 template 恢复，避免 UV4 回写后丢 LIC0
        const portable = fs.existsSync(tplPath)
            ? fs.readFileSync(tplPath, 'utf8')
            : raw.replace(
                  /^\s*PATH\s*=\s*".*?"\s*$/im,
                  'PATH="{{KEIL_ROOT}}\\C251\\"',
              );
        const out = portable.replace(/\r?\n/g, '\r\n');
        fs.writeFileSync(iniPath, out.endsWith('\r\n') ? out : `${out}\r\n`, 'utf8');
        return { ok: true, iniPath };
    }

    let c251Slash = path.resolve(path.join(keilRoot, 'C251'));
    if (!c251Slash.endsWith('\\')) c251Slash += '\\';
    let text = raw.replace(/\{\{KEIL_ROOT\}\}/g, keilRoot);
    if (/^[ \t]*\[C251\][ \t]*\r?\nPATH="/im.test(text)) {
        text = text.replace(
            /^[ \t]*\[C251\][ \t]*\r?\nPATH="[^"]*"/im,
            `[C251]\r\nPATH="${c251Slash}"`,
        );
    } else {
        text = `${text.trimEnd()}\r\n[C251]\r\nPATH="${c251Slash}"\r\n`;
    }
    const out = text.replace(/\r?\n/g, '\r\n');
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

/** @type {number} */
let code;
try {
    if (selected.source === 'bundled') {
        const ini = writeToolsIni(selected.keilRoot, 'runtime');
        console.log('TOOLS.INI runtime:', ini.ok ? ini.iniPath : ini.message);
    }

    code = await new Promise((resolve, reject) => {
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
} finally {
    if (selected.source === 'bundled') {
        const restored = writeToolsIni(selected.keilRoot, 'portable');
        console.log('TOOLS.INI portable:', restored.ok ? restored.iniPath : restored.message);
    }
}

const log = fs.existsSync(logPath) ? fs.readFileSync(logPath, 'utf8') : '';
const ok = /0 Error\(s\)/i.test(log) && fs.existsSync(hexPath);
console.log('exitCode:', code);
console.log('hex:', fs.existsSync(hexPath) ? hexPath : 'MISSING');
console.log('--- log tail ---');
console.log(log.split(/\r?\n/).slice(-15).join('\n'));
if (selected.source === 'bundled') {
    const iniNow = fs.readFileSync(path.join(selected.keilRoot, 'TOOLS.INI'), 'utf8');
    const portable = /PATH="\{\{KEIL_ROOT\}\}\\C251\\"/i.test(iniNow);
    console.log('TOOLS.INI uses placeholder:', portable);
    if (!portable) {
        console.log('FAIL: TOOLS.INI still has machine path');
        process.exit(3);
    }
}
console.log(ok ? 'PASS' : 'FAIL');
process.exit(ok ? 0 : 2);
