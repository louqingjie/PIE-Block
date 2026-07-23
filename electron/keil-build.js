import { app } from 'electron';
import fs from 'node:fs';
import path from 'node:path';
import { spawn, execFile } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { promisify } from 'node:util';

const execFileAsync = promisify(execFile);
const __dirname = path.dirname(fileURLToPath(import.meta.url));

/** 培训模板工程相对 stc32g 的路径 */
const PROJECT_REL = path.join('Projects', '0000.培训模板');
const UV_PROJECT = path.join('MDK', 'Project_Template.uvproj');
const MAIN_C_REL = path.join('USER', 'src', 'main.c');
const HEX_REL = path.join('MDK', 'Objects', 'Project_Template.hex');

const DEFAULT_KEIL_ROOTS = [
    path.join(process.env.LOCALAPPDATA || '', 'Keil_v5'),
    'C:\\Keil_v5',
    'D:\\Keil_v5',
    'C:\\Keil',
    'D:\\Keil',
];

const CONFIG_FILE_NAME = 'keil-config.json';
/** 内置工具链相对仓库 / resources 的目录名 */
const BUNDLED_TOOLCHAIN_DIR = 'keil-toolchain';

/**
 * 用户配置文件路径（userData/keil-config.json）。
 * @returns {string}
 */
export function getConfigPath() {
    try {
        return path.join(app.getPath('userData'), CONFIG_FILE_NAME);
    } catch {
        // 非 Electron 环境（自检脚本）回退到临时目录语义
        return path.join(process.env.APPDATA || process.cwd(), 'pie-block-keil-config.json');
    }
}

/**
 * 是否已打包。非 Electron 环境下视为未打包。
 * @returns {boolean}
 */
function isAppPackaged() {
    try {
        return Boolean(app?.isPackaged);
    } catch {
        return false;
    }
}



/**
 * @typedef {{ customRoot?: string|null, customUv4?: string|null, customC251?: string|null }} KeilConfig
 */

/**
 * 读取用户手动配置的 Keil 路径。
 * @returns {KeilConfig}
 */
export function loadKeilConfig() {
    try {
        const p = getConfigPath();
        if (!fs.existsSync(p)) return {};
        const raw = JSON.parse(fs.readFileSync(p, 'utf8'));
        return {
            customRoot: typeof raw.customRoot === 'string' ? raw.customRoot : null,
            customUv4: typeof raw.customUv4 === 'string' ? raw.customUv4 : null,
            customC251: typeof raw.customC251 === 'string' ? raw.customC251 : null,
        };
    } catch {
        return {};
    }
}

/**
 * 保存用户 Keil 路径配置。
 * @param {KeilConfig} config
 */
export function saveKeilConfig(config) {
    const p = getConfigPath();
    fs.mkdirSync(path.dirname(p), { recursive: true });
    const next = {
        customRoot: config.customRoot || null,
        customUv4: config.customUv4 || null,
        customC251: config.customC251 || null,
    };
    fs.writeFileSync(p, JSON.stringify(next, null, 2), 'utf8');
    return next;
}

/** 清除手动路径，恢复自动探测。 */
export function clearKeilConfig() {
    return saveKeilConfig({});
}

/**
 * 解析 stc32g 固件库根目录（开发态用仓库内路径，打包态用 extraResources）。
 * @returns {string}
 */
export function getStc32gRoot() {
    if (isAppPackaged()) {
        return path.join(process.resourcesPath, 'stc32g');
    }
    return path.join(__dirname, '..', 'stc32g');
}

/**
 * 内置 Keil 工具链根目录（开发：vendor/keil-toolchain；打包：resources/keil-toolchain）。
 * @returns {string}
 */
export function getBundledKeilRoot() {
    if (isAppPackaged()) {
        return path.join(process.resourcesPath, BUNDLED_TOOLCHAIN_DIR);
    }
    return path.join(__dirname, '..', 'vendor', BUNDLED_TOOLCHAIN_DIR);
}

/**
 * 内置工具链是否包含 UV4 + C251。
 * @param {string} [root]
 * @returns {boolean}
 */
export function isBundledToolchainPresent(root = getBundledKeilRoot()) {
    if (!root || !fs.existsSync(root)) return false;
    const uv4 = path.join(root, 'UV4', 'UV4.exe');
    const c251 = path.join(root, 'C251', 'BIN', 'C251.EXE');
    return fs.existsSync(uv4) && fs.existsSync(c251);
}

/**
 * Keil TOOLS.INI PATH 值：绝对路径 + 尾随反斜杠。
 * @param {string} dir
 */
function normalizeKeilIniPath(dir) {
    let p = path.resolve(dir);
    if (!p.endsWith('\\') && !p.endsWith('/')) p += '\\';
    return p;
}

/**
 * 读取 TOOLS.INI 文本（去 BOM）。
 * @param {string} iniPath
 */
function readToolsIniText(iniPath) {
    let raw = fs.readFileSync(iniPath, 'utf8');
    if (raw.charCodeAt(0) === 0xfeff) raw = raw.slice(1);
    return raw;
}

/**
 * 提取 INI 段体（不含 [section] 行）。
 * @param {string} text
 * @param {string} section
 */
function extractIniSectionBody(text, section) {
    const re = new RegExp(
        `^[ \\t]*\\[${section}\\][ \\t]*\\r?\\n([\\s\\S]*?)(?=^[ \\t]*\\[|\\s*$)`,
        'im',
    );
    const m = text.match(re);
    return m ? m[1] : '';
}

/**
 * 过滤段体内的键（及空行）。
 * @param {string} body
 * @param {string[]} dropKeys
 */
function filterIniSectionBody(body, dropKeys = []) {
    const drop = new Set(dropKeys.map((k) => k.toUpperCase()));
    return String(body || '')
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

/**
 * 便携模板路径（仓库提交的是占位符版本；UV4 可能改写 TOOLS.INI）。
 * @param {string} keilRoot
 */
function getToolsIniTemplatePath(keilRoot) {
    return path.join(keilRoot, 'TOOLS.INI.template');
}

/**
 * 读取便携模板（优先 TOOLS.INI.template，否则从当前 TOOLS.INI 推导并尽量保留 LIC0）。
 * @param {string} keilRoot
 */
function readPortableTemplateText(keilRoot) {
    const tpl = getToolsIniTemplatePath(keilRoot);
    if (fs.existsSync(tpl)) return readToolsIniText(tpl);

    const ini = path.join(keilRoot, 'TOOLS.INI');
    const text = fs.existsSync(ini) ? readToolsIniText(ini) : '';
    const uv2Body = filterIniSectionBody(extractIniSectionBody(text, 'UV2'), [
        'PATH',
        'RTEPATH',
        'CMSIS_TOOLBOX',
        'ARMSEL',
        'USERTE',
    ]);
    const c251Body = filterIniSectionBody(extractIniSectionBody(text, 'C251'), ['PATH']);
    return [
        '; pie-block bundled Keil C251/UV4 toolchain (portable)',
        '; Do not commit machine-absolute PATH. Use {{KEIL_ROOT}} placeholder.',
        '[UV2]',
        ...(uv2Body.length ? uv2Body : ['CDB0=UV4\\STC.CDB ("STC MCU Database")']),
        '[C251]',
        'PATH="{{KEIL_ROOT}}\\C251\\"',
        ...(c251Body.length ? c251Body : ['VERSION=5.60']),
        '',
    ].join('\r\n');
}

/**
 * 运行时 TOOLS.INI：基于模板把 {{KEIL_ROOT}} 换成当前绝对路径。
 * @param {string} keilRoot
 */
export function buildRuntimeToolsIniText(keilRoot) {
    const root = path.resolve(keilRoot);
    const c251Slash = normalizeKeilIniPath(path.join(root, 'C251'));
    let text = readPortableTemplateText(root);
    text = text.replace(/\{\{KEIL_ROOT\}\}/g, root);
    // 双保险：段首 PATH 必须是绝对路径
    if (!/^[ \t]*\[C251\][ \t]*\r?\nPATH="/im.test(text)) {
        text = `${text.trimEnd()}\r\n[C251]\r\nPATH="${c251Slash}"\r\n`;
    } else {
        text = text.replace(
            /^[ \t]*\[C251\][ \t]*\r?\nPATH="[^"]*"/im,
            `[C251]\r\nPATH="${c251Slash}"`,
        );
    }
    return text.endsWith('\r\n') ? text : `${text}\r\n`;
}

/**
 * 写 TOOLS.INI（CRLF）。失败时返回 false。
 * @param {string} iniPath
 * @param {string} content
 */
function writeToolsIniFile(iniPath, content) {
    const out = content.replace(/\r?\n/g, '\r\n');
    fs.writeFileSync(iniPath, out.endsWith('\r\n') ? out : `${out}\r\n`, 'utf8');
}

/**
 * 编译前：把 PATH 临时写成当前机器绝对路径（UV4 需要）。
 * 探测阶段请勿调用，以免把本机路径写进仓库文件。
 *
 * @param {string} keilRoot
 * @returns {{ ok: boolean, toolsIni: string|null, message: string, writableRoot: string }}
 */
export function ensureBundledToolsIni(keilRoot) {
    return applyRuntimeToolsIni(keilRoot);
}

/**
 * @param {string} keilRoot
 */
export function applyRuntimeToolsIni(keilRoot) {
    const root = path.resolve(keilRoot);
    const srcIni = path.join(root, 'TOOLS.INI');
    // 允许仅有 template 时首次生成 TOOLS.INI
    if (!fs.existsSync(srcIni) && !fs.existsSync(getToolsIniTemplatePath(root))) {
        return {
            ok: false,
            toolsIni: null,
            message: `内置工具链缺少 TOOLS.INI / TOOLS.INI.template：${root}`,
            writableRoot: root,
        };
    }

    const out = buildRuntimeToolsIniText(root);
    try {
        writeToolsIniFile(srcIni, out);
        return {
            ok: true,
            toolsIni: srcIni,
            message: 'TOOLS.INI 已写入运行时绝对 PATH',
            writableRoot: root,
        };
    } catch {
        /* 只读 */
    }

    let userDataDir;
    try {
        userDataDir = app.getPath('userData');
    } catch {
        userDataDir = path.join(process.env.APPDATA || process.cwd(), 'pie-block');
    }
    const fallbackDir = path.join(userDataDir, 'keil-toolchain-runtime');
    const fallbackIni = path.join(fallbackDir, 'TOOLS.INI');
    try {
        fs.mkdirSync(fallbackDir, { recursive: true });
        writeToolsIniFile(fallbackIni, out);
        return {
            ok: true,
            toolsIni: fallbackIni,
            message:
                '内置 TOOLS.INI 只读，已写入 userData 副本；若批编译失败请使用可写 vendor/keil-toolchain。',
            writableRoot: root,
        };
    } catch (err) {
        return {
            ok: false,
            toolsIni: null,
            message: `无法写入 TOOLS.INI：${err.message}`,
            writableRoot: root,
        };
    }
}

/**
 * 编译后：恢复便携占位符，避免本机绝对路径残留在仓库/安装包中。
 * UV4 运行期间也可能回写 TOOLS.INI，因此结束后必须再规范化一次。
 *
 * @param {string} keilRoot
 * @returns {{ ok: boolean, toolsIni: string|null, message: string }}
 */
export function restorePortableToolsIni(keilRoot) {
    const root = path.resolve(keilRoot);
    const srcIni = path.join(root, 'TOOLS.INI');
    try {
        const portable = readPortableTemplateText(root);
        // 确保 template 也存在（旧包升级时补一份）
        const tpl = getToolsIniTemplatePath(root);
        if (!fs.existsSync(tpl)) {
            try {
                writeToolsIniFile(tpl, portable);
            } catch {
                /* ignore */
            }
        }
        writeToolsIniFile(srcIni, portable);
        return {
            ok: true,
            toolsIni: srcIni,
            message: 'TOOLS.INI 已从 template 恢复为便携占位符',
        };
    } catch (err) {
        return {
            ok: false,
            toolsIni: srcIni,
            message: `无法恢复便携 TOOLS.INI：${err.message}`,
        };
    }
}

/**
 * 解析内置工具链 UV4/C251。
 * 探测时只检查文件存在，不把绝对路径写入 TOOLS.INI。
 * @returns {{ uv4: string|null, c251: string|null, keilRoot: string|null, toolsIni: string|null, ready: boolean, message: string }}
 */
export function resolveBundledToolchain() {
    const keilRoot = getBundledKeilRoot();
    if (!isBundledToolchainPresent(keilRoot)) {
        return {
            uv4: null,
            c251: null,
            keilRoot: fs.existsSync(keilRoot) ? keilRoot : null,
            toolsIni: null,
            ready: false,
            message: `未找到内置工具链（期望 ${keilRoot}）。开发态请运行 node scripts/prepare-keil-toolchain.mjs`,
        };
    }
    const uv4 = path.join(keilRoot, 'UV4', 'UV4.exe');
    const c251 = path.join(keilRoot, 'C251', 'BIN', 'C251.EXE');
    const toolsIni = path.join(keilRoot, 'TOOLS.INI');
    const hasIni = fs.existsSync(toolsIni);
    return {
        uv4,
        c251,
        keilRoot,
        toolsIni: hasIni ? toolsIni : null,
        ready: Boolean(fs.existsSync(uv4) && fs.existsSync(c251) && hasIni),
        message: hasIni
            ? `内置工具链就绪：${keilRoot}`
            : `内置工具链缺少 TOOLS.INI：${toolsIni}`,
    };
}

/**
 * @returns {{ projectRoot: string, uvproj: string, mainC: string, hexPath: string, mdkDir: string }}
 */
export function getProjectPaths() {
    const projectRoot = path.join(getStc32gRoot(), PROJECT_REL);
    return {
        projectRoot,
        uvproj: path.join(projectRoot, UV_PROJECT),
        mainC: path.join(projectRoot, MAIN_C_REL),
        hexPath: path.join(projectRoot, HEX_REL),
        mdkDir: path.join(projectRoot, 'MDK'),
    };
}

/**
 * 从注册表读取 Keil 产品路径（Windows）。
 * @param {string} product 例如 C251 / MDK
 * @returns {Promise<string|null>}
 */
async function readKeilRegistryPath(product) {
    if (process.platform !== 'win32') return null;
    const key = `HKLM\\SOFTWARE\\WOW6432Node\\Keil\\Products\\${product}`;
    try {
        const { stdout } = await execFileAsync('reg', ['query', key, '/v', 'Path'], {
            windowsHide: true,
            timeout: 5000,
        });
        const match = stdout.match(/Path\s+REG_SZ\s+(.+)/i);
        return match ? match[1].trim() : null;
    } catch {
        return null;
    }
}

/**
 * 在候选根目录下查找 UV4.exe / C251.EXE。
 * @param {string[]} roots
 */
function findToolsInRoots(roots) {
    /** @type {string|null} */
    let uv4 = null;
    /** @type {string|null} */
    let c251 = null;
    /** @type {string|null} */
    let keilRoot = null;

    for (const root of roots) {
        if (!root || !fs.existsSync(root)) continue;
        const uv4Candidate = path.join(root, 'UV4', 'UV4.exe');
        const c251Candidate = path.join(root, 'C251', 'BIN', 'C251.EXE');
        if (!uv4 && fs.existsSync(uv4Candidate)) {
            uv4 = uv4Candidate;
            keilRoot = root;
        }
        if (!c251 && fs.existsSync(c251Candidate)) {
            c251 = c251Candidate;
            if (!keilRoot) keilRoot = root;
        }
        if (uv4 && c251) break;
    }

    return { uv4, c251, keilRoot };
}

/**
 * 从用户选择的路径解析工具链。
 * 支持：
 * - UV4.exe 文件
 * - C251.EXE 文件
 * - Keil 根目录（含 UV4/、C251/）
 * - C251 目录（.../C251）
 * - UV4 目录（.../UV4）
 * @param {string} selectedPath
 * @returns {{ ok: boolean, customRoot?: string|null, customUv4?: string|null, customC251?: string|null, message: string }}
 */
export function resolveSelection(selectedPath) {
    if (!selectedPath || typeof selectedPath !== 'string') {
        return { ok: false, message: '未选择路径' };
    }
    const selected = path.resolve(selectedPath.trim());
    if (!fs.existsSync(selected)) {
        return { ok: false, message: `路径不存在：${selected}` };
    }

    const base = path.basename(selected).toLowerCase();
    const stat = fs.statSync(selected);

    /** @type {string|null} */
    let customUv4 = null;
    /** @type {string|null} */
    let customC251 = null;
    /** @type {string|null} */
    let customRoot = null;

    if (stat.isFile()) {
        if (base === 'uv4.exe') {
            customUv4 = selected;
            // .../Keil_v5/UV4/UV4.exe → root = Keil_v5
            customRoot = path.dirname(path.dirname(selected));
        } else if (base === 'c251.exe') {
            customC251 = selected;
            // .../Keil_v5/C251/BIN/C251.EXE → root = Keil_v5
            customRoot = path.dirname(path.dirname(path.dirname(selected)));
        } else {
            return {
                ok: false,
                message: '请选择 UV4.exe、C251.EXE，或 Keil 安装目录（Keil_v5）。',
            };
        }
    } else {
        // 目录
        if (fs.existsSync(path.join(selected, 'UV4.exe'))) {
            // 选中了 UV4 目录
            customUv4 = path.join(selected, 'UV4.exe');
            customRoot = path.dirname(selected);
        } else if (fs.existsSync(path.join(selected, 'BIN', 'C251.EXE'))) {
            // 选中了 C251 目录
            customC251 = path.join(selected, 'BIN', 'C251.EXE');
            customRoot = path.dirname(selected);
        } else if (
            fs.existsSync(path.join(selected, 'UV4', 'UV4.exe')) ||
            fs.existsSync(path.join(selected, 'C251', 'BIN', 'C251.EXE'))
        ) {
            // 选中了 Keil 根目录
            customRoot = selected;
        } else {
            // 再向上/向下试一层常见结构
            const parent = path.dirname(selected);
            if (fs.existsSync(path.join(parent, 'UV4', 'UV4.exe'))) {
                customRoot = parent;
            } else {
                return {
                    ok: false,
                    message:
                        '无法识别为 Keil 目录。请选择含 UV4 与 C251 的安装根目录，或直接选 UV4.exe。',
                };
            }
        }
    }

    // 用 root 补全另一侧工具
    if (customRoot) {
        const found = findToolsInRoots([customRoot]);
        if (!customUv4 && found.uv4) customUv4 = found.uv4;
        if (!customC251 && found.c251) customC251 = found.c251;
    }

    // 若只有 uv4，尝试从同级找 c251
    if (customUv4 && !customRoot) {
        customRoot = path.dirname(path.dirname(customUv4));
        const found = findToolsInRoots([customRoot]);
        if (!customC251 && found.c251) customC251 = found.c251;
    }

    if (!customUv4 && !customC251 && !customRoot) {
        return { ok: false, message: '未能解析 Keil 工具路径' };
    }

    // 至少要有 UV4 才能批编译
    if (!customUv4 || !fs.existsSync(customUv4)) {
        return {
            ok: false,
            message: '已识别路径，但未找到 UV4.exe。请选择 Keil 根目录或 UV4.exe。',
            customRoot,
            customUv4,
            customC251,
        };
    }

    return {
        ok: true,
        customRoot,
        customUv4,
        customC251: customC251 && fs.existsSync(customC251) ? customC251 : null,
        message: `已设置：${customUv4}`,
    };
}

/**
 * 读取 C251 版本号（尽力而为）。
 * @param {string|null} c251Path
 * @returns {Promise<string|null>}
 */
async function readC251Version(c251Path) {
    if (!c251Path || !fs.existsSync(c251Path)) return null;
    try {
        await execFileAsync(c251Path, [], { windowsHide: true, timeout: 5000 });
    } catch (err) {
        const text = `${err.stdout || ''}\n${err.stderr || ''}\n${err.message || ''}`;
        const m = text.match(/C251 COMPILER\s+(V[\d.]+)/i);
        if (m) return m[1];
    }
    return null;
}

/**
 * 探测 Keil μVision / C251 工具链。
 * 优先级：内置工具链 > 用户手动路径 > 注册表 > 常见安装目录。
 * 若设置 options.preferManual，则手动路径优先于内置（用于用户主动指定后）。
 * 若设置 options.bundledOnly，则仅使用内置。
 *
 * @param {{ preferManual?: boolean, bundledOnly?: boolean }} [options]
 */
export async function detectKeil(options = {}) {
    const paths = getProjectPaths();
    const config = loadKeilConfig();
    const hasManual = Boolean(config.customUv4 || config.customRoot || config.customC251);
    const preferManual = Boolean(options.preferManual && hasManual);
    const bundledOnly = Boolean(options.bundledOnly);

    const bundled = resolveBundledToolchain();

    /** @type {{ uv4: string|null, c251: string|null, keilRoot: string|null }} */
    let tools = { uv4: null, c251: null, keilRoot: null };
    /** @type {'bundled'|'manual'|'auto'|'none'} */
    let source = 'none';

    // 内置优先；用户配置了手动路径时尊重手动（便于覆盖内置问题）
    const pickBundled = bundled.ready && !hasManual && !preferManual;

    if (bundledOnly) {
        if (bundled.ready) {
            tools = { uv4: bundled.uv4, c251: bundled.c251, keilRoot: bundled.keilRoot };
            source = 'bundled';
        }
    } else if (pickBundled) {
        tools = { uv4: bundled.uv4, c251: bundled.c251, keilRoot: bundled.keilRoot };
        source = 'bundled';
    } else {
        const roots = [...DEFAULT_KEIL_ROOTS];
        const c251Reg = await readKeilRegistryPath('C251');
        if (c251Reg) {
            roots.unshift(path.dirname(c251Reg));
            roots.unshift(c251Reg);
        }
        if (config.customRoot) roots.unshift(config.customRoot);

        tools = findToolsInRoots(roots);

        if (config.customUv4 && fs.existsSync(config.customUv4)) {
            tools = {
                ...tools,
                uv4: config.customUv4,
                keilRoot:
                    config.customRoot ||
                    tools.keilRoot ||
                    path.dirname(path.dirname(config.customUv4)),
            };
        }
        if (config.customC251 && fs.existsSync(config.customC251)) {
            tools = {
                ...tools,
                c251: config.customC251,
                keilRoot:
                    tools.keilRoot ||
                    config.customRoot ||
                    path.dirname(path.dirname(path.dirname(config.customC251))),
            };
        }

        if (hasManual && tools.uv4) {
            source = 'manual';
        } else if (tools.uv4) {
            source = 'auto';
        } else if (bundled.ready) {
            // 手动无效时回退内置
            tools = { uv4: bundled.uv4, c251: bundled.c251, keilRoot: bundled.keilRoot };
            source = 'bundled';
        }
    }

    const c251Version = await readC251Version(tools.c251);

    const projectReady =
        fs.existsSync(paths.uvproj) &&
        fs.existsSync(paths.mainC) &&
        fs.existsSync(path.dirname(paths.mainC));

    const found = Boolean(tools.uv4 && fs.existsSync(tools.uv4));
    const c251Ok = Boolean(tools.c251 && fs.existsSync(tools.c251));

    let message = '';
    if (!found) {
        if (bundledOnly) {
            message = bundled.message || '未找到内置 Keil 工具链';
        } else if (hasManual) {
            message = '已配置手动路径，但未找到可用的 UV4.exe，请重新选择。';
        } else {
            message =
                '未检测到内置或本机 Keil。可运行 prepare 脚本准备内置工具链，或点击「Keil 路径」选择 UV4.exe。';
        }
    } else if (!projectReady) {
        message = `工程模板不完整：${paths.projectRoot}`;
    } else if (!c251Ok) {
        message =
            source === 'manual'
                ? 'UV4 已就绪（手动），未找到 C251.EXE，编译可能失败。'
                : 'UV4 已就绪，未找到 C251.EXE。';
    } else {
        const tag =
            source === 'bundled' ? '内置' : source === 'manual' ? '手动' : '自动';
        message = `已就绪（${tag}）：C251 ${c251Version || '已安装'}`;
    }

    return {
        found,
        uv4: tools.uv4,
        c251: tools.c251,
        keilRoot: tools.keilRoot,
        c251Version,
        projectReady,
        projectRoot: paths.projectRoot,
        uvproj: paths.uvproj,
        mainC: paths.mainC,
        hexPath: paths.hexPath,
        message,
        source: found ? source : 'none',
        bundled: {
            root: bundled.keilRoot || getBundledKeilRoot(),
            ready: bundled.ready,
            uv4: bundled.uv4,
            c251: bundled.c251,
            toolsIni: bundled.toolsIni,
            message: bundled.message,
        },
        config: {
            customRoot: config.customRoot || null,
            customUv4: config.customUv4 || null,
            customC251: config.customC251 || null,
            configPath: getConfigPath(),
        },
    };
}

/**
 * 应用用户选择的路径并保存。
 * @param {string} selectedPath
 */
export async function applyKeilSelection(selectedPath) {
    const resolved = resolveSelection(selectedPath);
    if (!resolved.ok) {
        return {
            success: false,
            message: resolved.message,
            info: await detectKeil(),
        };
    }
    saveKeilConfig({
        customRoot: resolved.customRoot || null,
        customUv4: resolved.customUv4 || null,
        customC251: resolved.customC251 || null,
    });
    const info = await detectKeil();
    return {
        success: info.found,
        message: resolved.message,
        info,
    };
}

/**
 * 将生成的 C 代码写入工程 main.c。
 * @param {string} code
 */
export function writeMainC(code) {
    const { mainC } = getProjectPaths();
    fs.mkdirSync(path.dirname(mainC), { recursive: true });
    const normalized = String(code ?? '').replace(/\r?\n/g, '\r\n');
    fs.writeFileSync(mainC, normalized, 'utf8');
    return mainC;
}

/**
 * 运行 UV4 批编译。
 * @param {string} uv4Path
 * @param {string} uvprojPath
 * @param {string} logPath
 * @param {number} [timeoutMs]
 * @param {{ keilRoot?: string|null }} [envOpts]
 * @returns {Promise<{ exitCode: number, log: string }>}
 */
function runUv4Build(uv4Path, uvprojPath, logPath, timeoutMs = 120000, envOpts = {}) {
    return new Promise((resolve, reject) => {
        try {
            if (fs.existsSync(logPath)) fs.unlinkSync(logPath);
        } catch {
            /* ignore */
        }

        /** @type {NodeJS.ProcessEnv} */
        const env = { ...process.env };
        if (envOpts.keilRoot) {
            env.KEIL_ROOT = envOpts.keilRoot;
            env.UV2_ROOT = envOpts.keilRoot;
        }

        const child = spawn(uv4Path, ['-b', uvprojPath, '-o', logPath], {
            cwd: path.dirname(uvprojPath),
            windowsHide: true,
            stdio: 'ignore',
            env,
        });

        const timer = setTimeout(() => {
            child.kill();
            reject(new Error(`Keil 编译超时（>${Math.round(timeoutMs / 1000)}s）`));
        }, timeoutMs);

        child.on('error', (err) => {
            clearTimeout(timer);
            reject(err);
        });

        child.on('close', (code) => {
            clearTimeout(timer);
            let log = '';
            if (fs.existsSync(logPath)) {
                try {
                    log = fs.readFileSync(logPath, 'utf8');
                } catch {
                    log = fs.readFileSync(logPath, 'latin1');
                }
            }
            resolve({ exitCode: code ?? 1, log });
        });
    });
}

/**
 * 从编译日志中提取错误/警告摘要。
 * @param {string} log
 */
function summarizeLog(log) {
    const lines = String(log || '').split(/\r?\n/);
    const errors = lines.filter((l) => /error/i.test(l) && !/0 Error/i.test(l));
    const warnings = lines.filter((l) => /warning/i.test(l) && !/0 Warning/i.test(l));
    const summaryLine =
        lines.find((l) => /Error\(s\).*Warning\(s\)/i.test(l)) ||
        lines.find((l) => /-\s*\d+\s*Error/i.test(l)) ||
        '';
    const success = /0 Error\(s\)/i.test(log) || /-\s*0\s*Error/i.test(log);
    return { success, errors, warnings, summaryLine };
}

/**
 * 完整编译流程：写 main.c → UV4 批编译 → 返回 hex / 日志。
 * @param {string} code 生成的 C 源码
 * @param {{ uv4?: string|null, bundledOnly?: boolean }} [options]
 */
export async function compileWithKeil(code, options = {}) {
    const info = await detectKeil({
        bundledOnly: Boolean(options.bundledOnly),
    });
    const uv4 = options.uv4 || info.uv4;
    const paths = getProjectPaths();

    if (!uv4 || !fs.existsSync(uv4)) {
        return {
            success: false,
            stage: 'detect',
            message:
                info.source === 'none' && info.bundled && !info.bundled.ready
                    ? info.bundled.message ||
                      '未找到 UV4.exe。请准备内置工具链或点击「Keil 路径」手动选择。'
                    : '未找到 UV4.exe。请点击「Keil 路径」手动选择安装目录或 UV4.exe。',
            log: '',
            hexPath: null,
            mainC: null,
            summary: null,
            source: info.source,
        };
    }
    if (!info.projectReady) {
        return {
            success: false,
            stage: 'project',
            message: info.message,
            log: '',
            hexPath: null,
            mainC: null,
            summary: null,
            source: info.source,
        };
    }
    if (!code || !String(code).trim()) {
        return {
            success: false,
            stage: 'source',
            message: '生成的 C 代码为空，请先在图形区添加积木。',
            log: '',
            hexPath: null,
            mainC: null,
            summary: null,
            source: info.source,
        };
    }

    let mainCPath;
    try {
        mainCPath = writeMainC(code);
    } catch (err) {
        return {
            success: false,
            stage: 'write',
            message: `写入 main.c 失败：${err.message}`,
            log: '',
            hexPath: null,
            mainC: null,
            summary: null,
            source: info.source,
        };
    }

    const logPath = path.join(paths.mdkDir, 'pie_block_build.log');
    /** @type {{ exitCode: number, log: string }} */
    let buildResult;
    const usedBundled = info.source === 'bundled' && info.keilRoot;
    try {
        // 仅编译期间写入本机绝对 PATH；结束后恢复 {{KEIL_ROOT}} 占位符
        if (usedBundled) {
            const applied = applyRuntimeToolsIni(info.keilRoot);
            if (!applied.ok) {
                return {
                    success: false,
                    stage: 'tools-ini',
                    message: applied.message,
                    log: '',
                    hexPath: null,
                    mainC: mainCPath,
                    summary: null,
                    source: info.source,
                };
            }
        }
        buildResult = await runUv4Build(uv4, paths.uvproj, logPath, 120000, {
            keilRoot: info.keilRoot,
        });
    } catch (err) {
        return {
            success: false,
            stage: 'build',
            message: err.message || 'Keil 编译进程失败',
            log: '',
            hexPath: null,
            mainC: mainCPath,
            summary: null,
            source: info.source,
        };
    } finally {
        if (usedBundled) {
            try {
                restorePortableToolsIni(info.keilRoot);
            } catch {
                /* ignore */
            }
        }
    }

    const summary = summarizeLog(buildResult.log);
    const hexExists = fs.existsSync(paths.hexPath);
    const ok = /0 Error\(s\)/i.test(buildResult.log) && hexExists;
    const sizeMatch = buildResult.log.match(/Program Size:[^\r\n]+/i);

    return {
        success: ok,
        stage: 'done',
        message: ok
            ? `编译成功：${path.basename(paths.hexPath)}`
            : summary.summaryLine ||
              (hexExists ? '编译可能存在错误，请查看日志。' : '编译失败，未生成 hex 文件。'),
        log: buildResult.log,
        hexPath: hexExists ? paths.hexPath : null,
        mainC: mainCPath,
        exitCode: buildResult.exitCode,
        uv4Used: uv4,
        source: info.source,
        summary: {
            ...summary,
            success: ok,
            programSize: sizeMatch ? sizeMatch[0] : null,
        },
    };
}
