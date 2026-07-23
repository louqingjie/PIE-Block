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

/**
 * 用户配置文件路径（userData/keil-config.json）。
 * @returns {string}
 */
export function getConfigPath() {
    return path.join(app.getPath('userData'), CONFIG_FILE_NAME);
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
    if (app.isPackaged) {
        return path.join(process.resourcesPath, 'stc32g');
    }
    return path.join(__dirname, '..', 'stc32g');
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
 * 探测本机 Keil μVision / C251 工具链。
 * 优先级：用户手动路径 > 注册表 > 常见安装目录。
 */
export async function detectKeil() {
    const paths = getProjectPaths();
    const config = loadKeilConfig();
    const roots = [...DEFAULT_KEIL_ROOTS];

    const c251Reg = await readKeilRegistryPath('C251');
    if (c251Reg) {
        roots.unshift(path.dirname(c251Reg));
        roots.unshift(c251Reg);
    }

    // 用户手动根目录优先
    if (config.customRoot) {
        roots.unshift(config.customRoot);
    }

    let tools = findToolsInRoots(roots);

    // 用户直接指定的 exe 覆盖自动结果
    if (config.customUv4 && fs.existsSync(config.customUv4)) {
        tools = {
            ...tools,
            uv4: config.customUv4,
            keilRoot: config.customRoot || tools.keilRoot || path.dirname(path.dirname(config.customUv4)),
        };
    }
    if (config.customC251 && fs.existsSync(config.customC251)) {
        tools = {
            ...tools,
            c251: config.customC251,
            keilRoot: tools.keilRoot || config.customRoot || path.dirname(path.dirname(path.dirname(config.customC251))),
        };
    }

    // 手动只给了 uv4 时，允许 found 以 uv4 为主（C251 由 UV4 工程间接使用）
    const hasManual = Boolean(config.customUv4 || config.customRoot || config.customC251);
    const c251Version = await readC251Version(tools.c251);

    const projectReady =
        fs.existsSync(paths.uvproj) &&
        fs.existsSync(paths.mainC) &&
        fs.existsSync(path.dirname(paths.mainC));

    // 批编译硬需求是 UV4；C251 建议存在
    const found = Boolean(tools.uv4 && fs.existsSync(tools.uv4));
    const c251Ok = Boolean(tools.c251 && fs.existsSync(tools.c251));

    let message = '';
    if (!found) {
        message = hasManual
            ? '已配置手动路径，但未找到可用的 UV4.exe，请重新选择。'
            : '未检测到 Keil μVision / C251。可点击「Keil 路径」手动选择安装目录或 UV4.exe。';
    } else if (!projectReady) {
        message = `工程模板不完整：${paths.projectRoot}`;
    } else if (!c251Ok) {
        message = hasManual
            ? `UV4 已就绪（手动），未找到 C251.EXE，编译可能失败。`
            : `UV4 已就绪，未找到 C251.EXE。`;
    } else {
        const src = hasManual ? '手动' : '自动';
        message = `已就绪（${src}）：C251 ${c251Version || '已安装'}`;
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
        source: hasManual ? 'manual' : found ? 'auto' : 'none',
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
 * @returns {Promise<{ exitCode: number, log: string }>}
 */
function runUv4Build(uv4Path, uvprojPath, logPath, timeoutMs = 120000) {
    return new Promise((resolve, reject) => {
        try {
            if (fs.existsSync(logPath)) fs.unlinkSync(logPath);
        } catch {
            /* ignore */
        }

        const child = spawn(uv4Path, ['-b', uvprojPath, '-o', logPath], {
            cwd: path.dirname(uvprojPath),
            windowsHide: true,
            stdio: 'ignore',
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
 * @param {{ uv4?: string|null }} [options]
 */
export async function compileWithKeil(code, options = {}) {
    const info = await detectKeil();
    const uv4 = options.uv4 || info.uv4;
    const paths = getProjectPaths();

    if (!uv4 || !fs.existsSync(uv4)) {
        return {
            success: false,
            stage: 'detect',
            message: '未找到 UV4.exe。请点击「Keil 路径」手动选择安装目录或 UV4.exe。',
            log: '',
            hexPath: null,
            mainC: null,
            summary: null,
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
        };
    }

    const logPath = path.join(paths.mdkDir, 'pie_block_build.log');
    /** @type {{ exitCode: number, log: string }} */
    let buildResult;
    try {
        buildResult = await runUv4Build(uv4, paths.uvproj, logPath);
    } catch (err) {
        return {
            success: false,
            stage: 'build',
            message: err.message || 'Keil 编译进程失败',
            log: '',
            hexPath: null,
            mainC: mainCPath,
            summary: null,
        };
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
        summary: {
            ...summary,
            success: ok,
            programSize: sizeMatch ? sizeMatch[0] : null,
        },
    };
}
