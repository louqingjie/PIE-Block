/**
 * 从本机已授权 Keil 安装同步「批编译最小子集」到 vendor/keil-toolchain。
 *
 * 用法：
 *   node scripts/prepare-keil-toolchain.mjs
 *   node scripts/prepare-keil-toolchain.mjs --source "C:\\Users\\...\\Keil_v5"
 *   node scripts/prepare-keil-toolchain.mjs --force
 *
 * 注意：二进制受 Keil 授权约束，默认不进 git；仅在你已有可再分发授权时打包分发。
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';

const execFileAsync = promisify(execFile);
const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.join(__dirname, '..');
const destRoot = path.join(repoRoot, 'vendor', 'keil-toolchain');

const args = process.argv.slice(2);
const force = args.includes('--force');
const srcIdx = args.indexOf('--source');
const sourceArg = srcIdx >= 0 ? args[srcIdx + 1] : null;

/**
 * UV4 批编译可跳过的大型/无关文件。
 * 注意：UV4.exe 的 PE 导入表直接依赖 armlm.dll，不可排除。
 */
const UV4_SKIP_NAMES = new Set([
    'packinstaller.exe',
    'packunzip.exe',
    'uv2csolution.exe',
    'doxyindex.exe',
    'svdconv.exe',
    'sysviewer.dll',
    'uv4.chm',
    'uv4jp.chm',
    'pack-requirements.yml',
]);

/** armlm/ 目录内有 armlm 运行时依赖，需保留；仅跳过文档/许可管理大工具 */
const UV4_SKIP_DIRS = new Set(['flexnet', 'lint']);

/** C251/BIN 跳过备份 */
const C251_BIN_SKIP = new Set(['c251.exe.bk1']);

function log(...m) {
    console.log('[prepare-keil]', ...m);
}

function fail(msg) {
    console.error('[prepare-keil] ERROR:', msg);
    process.exit(1);
}

async function findDefaultSource() {
    if (sourceArg) return path.resolve(sourceArg);

    const candidates = [
        path.join(process.env.LOCALAPPDATA || '', 'Keil_v5'),
        'C:\\Keil_v5',
        'D:\\Keil_v5',
        'C:\\Keil',
        'D:\\Keil',
    ];

    try {
        const { stdout } = await execFileAsync(
            'reg',
            ['query', 'HKLM\\SOFTWARE\\WOW6432Node\\Keil\\Products\\C251', '/v', 'Path'],
            { windowsHide: true },
        );
        const m = stdout.match(/Path\s+REG_SZ\s+(.+)/i);
        if (m) {
            const c251 = m[1].trim();
            candidates.unshift(path.dirname(c251), c251);
        }
    } catch {
        /* ignore */
    }

    for (const root of candidates) {
        if (!root) continue;
        const uv4 = path.join(root, 'UV4', 'UV4.exe');
        const c251 = path.join(root, 'C251', 'BIN', 'C251.EXE');
        if (fs.existsSync(uv4) && fs.existsSync(c251)) return root;
    }
    return null;
}

function ensureDir(p) {
    fs.mkdirSync(p, { recursive: true });
}

function copyFile(src, dest) {
    ensureDir(path.dirname(dest));
    fs.copyFileSync(src, dest);
}

/**
 * 递归复制目录，支持按名称跳过。
 * @param {string} src
 * @param {string} dest
 * @param {{ skipNames?: Set<string>, skipDirs?: Set<string> }} [opts]
 * @returns {{ files: number, bytes: number }}
 */
function copyTree(src, dest, opts = {}) {
    const skipNames = opts.skipNames || new Set();
    const skipDirs = opts.skipDirs || new Set();
    let files = 0;
    let bytes = 0;

    function walk(from, to) {
        const st = fs.statSync(from);
        if (st.isDirectory()) {
            const base = path.basename(from).toLowerCase();
            if (skipDirs.has(base)) return;
            ensureDir(to);
            for (const name of fs.readdirSync(from)) {
                walk(path.join(from, name), path.join(to, name));
            }
            return;
        }
        if (skipNames.has(path.basename(from).toLowerCase())) return;
        ensureDir(path.dirname(to));
        fs.copyFileSync(from, to);
        files += 1;
        bytes += st.size;
    }

    walk(src, dest);
    return { files, bytes };
}

/**
 * 生成便携 TOOLS.INI / TOOLS.INI.template：只保留 [UV2] + [C251]。
 * 关键：μVision 要求 [C251] 段的第一项必须是 PATH=（与官方文件一致）。
 * PATH 使用占位符 {{KEIL_ROOT}}，编译时临时改写，结束后从 template 恢复。
 * 保留 LIC0 等许可证字段，否则会变成评估版 2KB 限制。
 *
 * @param {string} srcIni
 * @param {string} destDir vendor/keil-toolchain
 */
function writePortableToolsIni(srcIni, destDir) {
    const raw = fs.readFileSync(srcIni, 'utf8');
    const uv2 = extractSection(raw, 'UV2');
    const c251 = extractSection(raw, 'C251');

    // UV2：去掉本机绝对路径项；保留 CDB / 组织信息
    const uv2Body = filterSectionBody(uv2, [
        'PATH',
        'RTEPATH',
        'CMSIS_TOOLBOX',
        'ARMSEL',
        'USERTE',
    ]);
    // C251：去掉旧 PATH，占位 PATH 写在段首；保留 VERSION/LIC0/TDRV 等
    const c251Body = filterSectionBody(c251, ['PATH']);

    const rebuilt = [
        '; pie-block bundled Keil C251/UV4 toolchain (portable)',
        '; Do not commit machine-absolute PATH. Use {{KEIL_ROOT}} placeholder.',
        '; Runtime compile rewrites TOOLS.INI; restore from TOOLS.INI.template after build.',
        '[UV2]',
        ...uv2Body,
        '[C251]',
        'PATH="{{KEIL_ROOT}}\\C251\\"',
        ...c251Body,
        '',
    ].join('\r\n');

    ensureDir(destDir);
    const destIni = path.join(destDir, 'TOOLS.INI');
    const destTpl = path.join(destDir, 'TOOLS.INI.template');
    fs.writeFileSync(destIni, rebuilt, 'utf8');
    fs.writeFileSync(destTpl, rebuilt, 'utf8');
}

/**
 * @param {string} raw
 * @param {string} name
 */
function extractSection(raw, name) {
    const re = new RegExp(`\\[${name}\\]([\\s\\S]*?)(?=\\n\\[|$)`, 'i');
    const m = raw.match(re);
    return m ? m[1] : '';
}

/**
 * @param {string} body
 * @param {string[]} dropKeys
 */
function filterSectionBody(body, dropKeys) {
    const drop = new Set(dropKeys.map((k) => k.toUpperCase()));
    return body
        .split(/\r?\n/)
        .map((l) => l.trimEnd())
        .filter((l) => {
            if (!l.trim()) return false;
            if (l.trim().startsWith(';')) return true;
            const key = l.split('=')[0]?.trim().toUpperCase();
            if (key && drop.has(key)) return false;
            return true;
        });
}

function formatMb(n) {
    return `${(n / (1024 * 1024)).toFixed(1)} MB`;
}

/**
 * 从 WinSxS 复制 VC80 CRT 旁路 DLL（msvcp80/msvcm80）。
 * UV4 的 Microsoft.VC80.CRT.manifest 需要这三项；Keil 安装目录通常只带 msvcr80。
 * @param {string} uv4Dest
 * @returns {{ files: number, bytes: number }}
 */
function ensureVc80Crt(uv4Dest) {
    const need = ['msvcp80.dll', 'msvcm80.dll'];
    let files = 0;
    let bytes = 0;
    const winsxs = path.join(process.env.WINDIR || 'C:\\Windows', 'WinSxS');
    if (!fs.existsSync(winsxs)) return { files, bytes };

    /** @type {string|null} */
    let crtDir = null;
    try {
        // 优先 8.0.50727.* x86_microsoft.vc80.crt
        const dirs = fs
            .readdirSync(winsxs)
            .filter((d) => /^x86_microsoft\.vc80\.crt_/i.test(d))
            .sort()
            .reverse();
        for (const d of dirs) {
            const full = path.join(winsxs, d);
            if (fs.existsSync(path.join(full, 'msvcp80.dll')) && fs.existsSync(path.join(full, 'msvcm80.dll'))) {
                crtDir = full;
                break;
            }
        }
    } catch {
        return { files, bytes };
    }
    if (!crtDir) return { files, bytes };

    for (const name of need) {
        const dest = path.join(uv4Dest, name);
        if (fs.existsSync(dest)) continue;
        const from = path.join(crtDir, name);
        if (!fs.existsSync(from)) continue;
        copyFile(from, dest);
        const st = fs.statSync(dest);
        files += 1;
        bytes += st.size;
    }
    // msvcr80 一般已由 Keil UV4 目录提供
    return { files, bytes };
}

async function main() {
    if (process.platform !== 'win32') {
        fail('仅支持在 Windows 上从本机 Keil 同步工具链');
    }

    const source = await findDefaultSource();
    if (!source) {
        fail(
            '未找到本机 Keil_v5（需含 UV4\\UV4.exe 与 C251\\BIN\\C251.EXE）。请用 --source <Keil根目录>',
        );
    }

    const uv4Src = path.join(source, 'UV4');
    const c251Src = path.join(source, 'C251');
    const toolsIni = path.join(source, 'TOOLS.INI');
    if (!fs.existsSync(path.join(uv4Src, 'UV4.exe'))) fail(`缺少 ${path.join(uv4Src, 'UV4.exe')}`);
    if (!fs.existsSync(path.join(c251Src, 'BIN', 'C251.EXE'))) {
        fail(`缺少 ${path.join(c251Src, 'BIN', 'C251.EXE')}`);
    }
    if (!fs.existsSync(toolsIni)) fail(`缺少 ${toolsIni}`);

    if (fs.existsSync(destRoot) && !force) {
        const existingUv4 = path.join(destRoot, 'UV4', 'UV4.exe');
        if (fs.existsSync(existingUv4)) {
            log(`已存在 ${destRoot}，使用 --force 覆盖`);
            log('OK (skipped)');
            process.exit(0);
        }
    }

    if (fs.existsSync(destRoot) && force) {
        log('清理旧目录…');
        fs.rmSync(destRoot, { recursive: true, force: true });
    }

    log('源:', source);
    log('目标:', destRoot);
    ensureDir(destRoot);

    let totalFiles = 0;
    let totalBytes = 0;

    log('复制 UV4（排除 FlexNet/大安装器；保留 armlm.dll）…');
    {
        const r = copyTree(uv4Src, path.join(destRoot, 'UV4'), {
            skipNames: UV4_SKIP_NAMES,
            skipDirs: UV4_SKIP_DIRS,
        });
        totalFiles += r.files;
        totalBytes += r.bytes;
        log(`  UV4: ${r.files} files, ${formatMb(r.bytes)}`);
    }

    log('补齐 VC80 CRT（msvcp80/msvcm80，供便携 UV4 加载）…');
    {
        const n = ensureVc80Crt(path.join(destRoot, 'UV4'));
        totalFiles += n.files;
        totalBytes += n.bytes;
        if (n.files) log(`  新增 CRT: ${n.files} files`);
        else log(`  CRT 已齐全或未找到 WinSxS 源（若 UV4 启动失败请装 vcredist 2005 x86）`);
    }

    log('复制 C251/BIN…');
    {
        const binSrc = path.join(c251Src, 'BIN');
        const binDest = path.join(destRoot, 'C251', 'BIN');
        ensureDir(binDest);
        for (const name of fs.readdirSync(binSrc)) {
            if (C251_BIN_SKIP.has(name.toLowerCase())) continue;
            const from = path.join(binSrc, name);
            const st = fs.statSync(from);
            if (!st.isFile()) continue;
            copyFile(from, path.join(binDest, name));
            totalFiles += 1;
            totalBytes += st.size;
        }
    }

    log('复制 C251/INC…');
    {
        const r = copyTree(path.join(c251Src, 'INC'), path.join(destRoot, 'C251', 'INC'));
        totalFiles += r.files;
        totalBytes += r.bytes;
    }

    log('复制 C251/LIB…');
    {
        const r = copyTree(path.join(c251Src, 'LIB'), path.join(destRoot, 'C251', 'LIB'), {
            // 调试/固定目录非批编译必需
            skipDirs: new Set(['fixdrk']),
        });
        totalFiles += r.files;
        totalBytes += r.bytes;
    }

    // 可选：若有 HLP 中的关键说明不必复制
    const licSrc = path.join(source, 'THIRD-PARTY-LICENSES_C251.txt');
    if (fs.existsSync(licSrc)) {
        copyFile(licSrc, path.join(destRoot, 'THIRD-PARTY-LICENSES_C251.txt'));
        totalFiles += 1;
    }

    log('生成便携 TOOLS.INI + TOOLS.INI.template…');
    writePortableToolsIni(toolsIni, destRoot);
    totalFiles += 2;

    // 清单
    const manifest = {
        createdAt: new Date().toISOString(),
        source,
        files: totalFiles,
        bytes: totalBytes,
        note: 'Licensed Keil binaries. Redistribute only with valid rights.',
    };
    fs.writeFileSync(path.join(destRoot, 'bundle-manifest.json'), JSON.stringify(manifest, null, 2), 'utf8');

    // 完整性检查
    const required = [
        path.join(destRoot, 'UV4', 'UV4.exe'),
        path.join(destRoot, 'UV4', 'armlm.dll'),
        path.join(destRoot, 'C251', 'BIN', 'C251.EXE'),
        path.join(destRoot, 'C251', 'BIN', 'L251.EXE'),
        path.join(destRoot, 'C251', 'BIN', 'OH251.EXE'),
        path.join(destRoot, 'C251', 'BIN', 'A251.EXE'),
        path.join(destRoot, 'TOOLS.INI'),
    ];
    for (const p of required) {
        if (!fs.existsSync(p)) fail(`同步后缺少必需文件：${p}`);
    }

    // 校验 [C251] PATH 在段首
    const iniText = fs.readFileSync(path.join(destRoot, 'TOOLS.INI'), 'utf8');
    if (!/^[ \t]*\[C251\][ \t]*\r?\nPATH=/im.test(iniText)) {
        fail('TOOLS.INI 中 [C251] 段首必须是 PATH=（μVision 硬性要求）');
    }

    log(`完成：${totalFiles} files, ${formatMb(totalBytes)}`);
    log('下一步：node electron/test-keil-compile.mjs --bundled-only');
}

main().catch((err) => {
    fail(err?.stack || String(err));
});
