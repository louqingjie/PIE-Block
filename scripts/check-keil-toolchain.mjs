/**
 * 打包前检查 vendor/keil-toolchain 是否齐全。
 * 用法：node scripts/check-keil-toolchain.mjs
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'vendor', 'keil-toolchain');
const required = [
    ['UV4', 'UV4.exe'],
    ['UV4', 'armlm.dll'],
    ['C251', 'BIN', 'C251.EXE'],
    ['C251', 'BIN', 'L251.EXE'],
    ['C251', 'BIN', 'OH251.EXE'],
    ['TOOLS.INI'],
];

if (!fs.existsSync(root)) {
    console.error(`[check-keil] 缺少内置工具链目录：${root}`);
    console.error('请先运行：node scripts/prepare-keil-toolchain.mjs');
    process.exit(1);
}

const missing = required
    .map((parts) => path.join(root, ...parts))
    .filter((p) => !fs.existsSync(p));

if (missing.length) {
    console.error('[check-keil] 内置工具链不完整，缺少：');
    for (const p of missing) console.error(' -', p);
    console.error('请运行：node scripts/prepare-keil-toolchain.mjs --force');
    process.exit(1);
}

console.log('[check-keil] OK:', root);
process.exit(0);
