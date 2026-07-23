/**
 * 无界面自检：探测 Keil 并用示例代码批编译。
 * 用法：node electron/test-keil-compile.mjs
 */
import { createRequire } from 'node:module';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import fs from 'node:fs';

// keil-build.js 依赖 electron.app，测试时用轻量 stub
const electronStub = {
    app: {
        isPackaged: false,
        getAppPath: () => path.join(path.dirname(fileURLToPath(import.meta.url)), '..'),
    },
};

// 通过自定义 loader 无法轻易替换 electron，这里内联最小实现复用逻辑
const __dirname = path.dirname(fileURLToPath(import.meta.url));
const root = path.join(__dirname, '..');

// 动态导入前 monkey-patch：用 Module 钩子不可靠，直接复制检测 + 编译调用路径
const { spawn } = await import('node:child_process');
const { execFile } = await import('node:child_process');
const { promisify } = await import('node:util');
const execFileAsync = promisify(execFile);

const projectRoot = path.join(root, 'stc32g', 'Projects', '0000.培训模板');
const uvproj = path.join(projectRoot, 'MDK', 'Project_Template.uvproj');
const mainC = path.join(projectRoot, 'USER', 'src', 'main.c');
const hexPath = path.join(projectRoot, 'MDK', 'Objects', 'Project_Template.hex');
const logPath = path.join(projectRoot, 'MDK', 'pie_block_build.log');

async function findUv4() {
    const roots = [
        path.join(process.env.LOCALAPPDATA || '', 'Keil_v5'),
        'C:\\Keil_v5',
        'D:\\Keil_v5',
    ];
    try {
        const { stdout } = await execFileAsync('reg', [
            'query',
            'HKLM\\SOFTWARE\\WOW6432Node\\Keil\\Products\\C251',
            '/v',
            'Path',
        ], { windowsHide: true });
        const m = stdout.match(/Path\s+REG_SZ\s+(.+)/i);
        if (m) roots.unshift(path.dirname(m[1].trim()));
    } catch { /* ignore */ }

    for (const r of roots) {
        const p = path.join(r, 'UV4', 'UV4.exe');
        if (fs.existsSync(p)) return p;
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

const uv4 = await findUv4();
console.log('UV4:', uv4);
console.log('uvproj exists:', fs.existsSync(uvproj));
if (!uv4 || !fs.existsSync(uvproj)) {
    console.error('FAIL: tools or project missing');
    process.exit(1);
}

fs.writeFileSync(mainC, SAMPLE.replace(/\r?\n/g, '\r\n'), 'utf8');
console.log('Wrote main.c');

if (fs.existsSync(logPath)) fs.unlinkSync(logPath);

const code = await new Promise((resolve, reject) => {
    const child = spawn(uv4, ['-b', uvproj, '-o', logPath], {
        cwd: path.dirname(uvproj),
        windowsHide: true,
        stdio: 'ignore',
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
