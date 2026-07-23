import { app } from 'electron';
import fs from 'node:fs';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { execFile } from 'node:child_process';
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
 * 探测本机 Keil μVision / C251 工具链。
 * @returns {Promise<{
 *   found: boolean,
 *   uv4: string|null,
 *   c251: string|null,
 *   keilRoot: string|null,
 *   c251Version: string|null,
 *   projectReady: boolean,
 *   projectRoot: string,
 *   uvproj: string,
 *   mainC: string,
 *   hexPath: string,
 *   message: string,
 * }>}
 */
export async function detectKeil() {
    const paths = getProjectPaths();
    const roots = [...DEFAULT_KEIL_ROOTS];

    const c251Reg = await readKeilRegistryPath('C251');
    if (c251Reg) {
        // 注册表 Path 指向 ...\C251，上一级才是 Keil_v5 根
        roots.unshift(path.dirname(c251Reg));
        roots.unshift(c251Reg);
    }

    const tools = findToolsInRoots(roots);
    let c251Version = null;
    if (tools.c251) {
        try {
            // C251 无参数会报 FATAL-ERROR，但 stdout/stderr 含版本行
            await execFileAsync(tools.c251, [], { windowsHide: true, timeout: 5000 });
        } catch (err) {
            const text = `${err.stdout || ''}\n${err.stderr || ''}\n${err.message || ''}`;
            const m = text.match(/C251 COMPILER\s+(V[\d.]+)/i);
            if (m) c251Version = m[1];
        }
    }

    const projectReady =
        fs.existsSync(paths.uvproj) &&
        fs.existsSync(paths.mainC) &&
        fs.existsSync(path.dirname(paths.mainC));

    const found = Boolean(tools.uv4 && tools.c251);
    let message = '';
    if (!found) {
        message = '未检测到 Keil μVision / C251。请安装 Keil C251 工具链后重试。';
    } else if (!projectReady) {
        message = `工程模板不完整：${paths.projectRoot}`;
    } else {
        message = `已就绪：C251 ${c251Version || '已安装'}，工程模板可用。`;
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
    };
}

/**
 * 将生成的 C 代码写入工程 main.c。
 * @param {string} code
 */
export function writeMainC(code) {
    const { mainC } = getProjectPaths();
    fs.mkdirSync(path.dirname(mainC), { recursive: true });
    // Keil / 源库习惯使用 CRLF；保留 UTF-8 内容
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

        // UV4 -b <project> -o <logfile>  ：无界面批编译
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
                // 构建日志多为系统 ANSI/本地编码，先按 utf8 读，失败再 latin1 兜底
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
            message: '未找到 UV4.exe，无法调用 Keil 编译器。',
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
    // 以日志 “0 Error(s)” + hex 文件存在作为成功判据（UV4 退出码有时也为 0）
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
        summary: {
            ...summary,
            success: ok,
            programSize: sizeMatch ? sizeMatch[0] : null,
        },
    };
}
