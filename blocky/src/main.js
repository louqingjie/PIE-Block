import * as Blockly from 'blockly';
import 'blockly/blocks';                 // 注册 Blockly 内置积木（if/while/数学/逻辑…）
import { javascriptGenerator } from 'blockly/javascript';

import './blocks/index.js';               // 注册自定义积木
import './generators/index.js';           // 注册 C 代码生成器
import { toolbox } from './toolbox.js';
import { generateC } from './generators/c_generator.js';
import {
    PROJECT_EXTENSION,
    buildProjectDocument,
    parseProjectDocument,
    nameFromPath,
    loadDefaultWorkspace,
    applyProjectToWorkspace,
    downloadTextFile,
    pickAndReadTextFile,
} from './project.js';
import './styles.css';

// 1. 注入工作区
const workspace = Blockly.inject('blockly-div', {
    toolbox,
    grid: { spacing: 20, length: 1, colour: '#222831', snap: true },
    zoom: { controls: true, wheel: true, startScale: 0.9 },
    trashcan: true,
    move: { scrollbars: true, drag: true, wheel: true },
    theme: Blockly.Theme.defineTheme('dark', {
        base: Blockly.Themes.Classic,
        componentStyles: {
            workspaceBackgroundColour: '#0d1117',
            toolboxBackgroundColour: '#13181f',
            toolboxForegroundColour: '#c9d1d9',
            flyoutBackgroundColour: '#1c2128',
            flyoutForegroundColour: '#c9d1d9',
            flyoutOpacity: 1,
            scrollbarColour: '#30363d',
            insertionMarkerColour: '#4ecdc4',
        },
    }),
});

// 2. 默认放置"初始化区"与"主循环区"两个不可删除容器，上下连接
loadDefaultWorkspace(workspace, Blockly);

// 3. 代码生成与展示
const codeArea = document.getElementById('code-preview');
let debounceTimer = null;

/** 更新顶栏芯片状态 LED */
function setChipState(state /* 'idle' | 'generating' | 'ok' | 'error' */) {
    document.body.classList.remove('state-generating', 'state-ok', 'state-error');
    if (state !== 'idle') document.body.classList.add(`state-${state}`);
}

let okResetTimer = null;

function refresh() {
    setChipState('generating');
    clearTimeout(okResetTimer);
    try {
        codeArea.textContent = generateC(workspace);
        setChipState('ok');
        // 3 秒后回到空闲，避免常亮绿色视觉疲劳
        okResetTimer = setTimeout(() => setChipState('idle'), 3000);
    } catch (err) {
        codeArea.textContent = '/* 生成出错: ' + err.message + ' */';
        setChipState('error');
    }
}

workspace.addChangeListener((event) => {
    if (event.type === Blockly.Events.UI) return;  // 跳过纯 UI 事件
    clearTimeout(debounceTimer);
    debounceTimer = setTimeout(refresh, 120);
});

document.getElementById('btn-generate').addEventListener('click', refresh);

document.getElementById('btn-copy').addEventListener('click', async () => {
    try {
        await navigator.clipboard.writeText(codeArea.textContent);
    } catch {
        /* 剪贴板可能被浏览器拒绝 */
    }
});

document.getElementById('btn-download').addEventListener('click', () => {
    const blob = new Blob([codeArea.textContent], { type: 'text/plain;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = 'main.c';
    a.click();
    URL.revokeObjectURL(url);
});

// ========== Keil C251 编译（仅 Electron 桌面端）==========
const btnCompile = document.getElementById('btn-compile');
const btnKeilPath = document.getElementById('btn-keil-path');
const btnKeilClear = document.getElementById('btn-keil-clear');
const btnOpenHex = document.getElementById('btn-open-hex');
const compileStatus = document.getElementById('compile-status');
const buildLogEl = document.getElementById('build-log');
const btnClearLog = document.getElementById('btn-clear-log');

/** @type {string|null} */
let lastHexPath = null;
/** 是否正在编译 */
let isCompiling = false;

const native = typeof window !== 'undefined' ? window.pieNative : null;
const canCompile = Boolean(native?.compile);

function setCompileStatus(text, kind = '') {
    if (!compileStatus) return;
    compileStatus.textContent = text || '';
    compileStatus.classList.remove('is-ok', 'is-error', 'is-busy');
    if (kind) compileStatus.classList.add(kind);
    if (text) compileStatus.title = text;
}

function setBuildLog(text) {
    if (!buildLogEl) return;
    buildLogEl.textContent = text || '';
    buildLogEl.scrollTop = buildLogEl.scrollHeight;
}

function setCompileUiBusy(busy) {
    isCompiling = busy;
    if (btnCompile) {
        btnCompile.disabled = busy || !canCompile;
        btnCompile.textContent = busy ? '编译中…' : '编译';
    }
    if (btnKeilPath) btnKeilPath.disabled = busy || !canCompile;
    if (btnKeilClear) btnKeilClear.disabled = busy || !canCompile;
}

/**
 * 根据 detectKeil 结果刷新状态栏与「重置路径」按钮。
 * @param {object|null|undefined} info
 */
function applyKeilInfo(info) {
    const hasManual =
        info?.source === 'manual' ||
        Boolean(info?.config?.customUv4 || info?.config?.customRoot);
    if (btnKeilClear) {
        btnKeilClear.classList.toggle('hidden', !hasManual);
    }

    if (!info?.found) {
        setCompileStatus(info?.message || '未检测到 Keil', 'is-error');
        if (btnCompile) {
            btnCompile.title =
                info?.message ||
                '未找到 UV4.exe。可准备内置工具链，或点击「Keil 路径」手动选择';
        }
        if (btnKeilPath && info?.config?.customUv4) {
            btnKeilPath.title = `当前手动：${info.config.customUv4}`;
        } else if (btnKeilPath) {
            btnKeilPath.title = info?.bundled?.ready
                ? '已检测到内置工具链；也可手动覆盖路径'
                : '手动选择 Keil 安装目录或 UV4.exe';
        }
        return;
    }

    if (!info.projectReady) {
        setCompileStatus('工程模板缺失', 'is-error');
        return;
    }

    const ver = info.c251Version ? `C251 ${info.c251Version}` : 'Keil 已就绪';
    const tag =
        info.source === 'bundled'
            ? '内置'
            : info.source === 'manual'
                ? '手动'
                : '自动';
    setCompileStatus(`${ver} · ${tag}`, 'is-ok');
    if (btnCompile) {
        btnCompile.title = info.uv4 ? `使用：${info.uv4}` : '使用 Keil C251 编译';
    }
    if (btnKeilPath) {
        if (info.source === 'bundled') {
            btnKeilPath.title = `当前使用内置工具链：${info.uv4 || ''}（点击可改用外部 Keil）`;
        } else {
            btnKeilPath.title = info.uv4
                ? `当前 UV4：${info.uv4}（点击可重新选择）`
                : '手动选择 Keil 安装目录或 UV4.exe';
        }
    }
}

if (!canCompile) {
    // 浏览器预览模式：无 Node/Keil，禁用编译
    if (btnCompile) {
        btnCompile.disabled = true;
        btnCompile.title = '请在 Electron 桌面端使用 Keil 编译';
    }
    if (btnKeilPath) {
        btnKeilPath.disabled = true;
        btnKeilPath.title = '请在 Electron 桌面端配置 Keil 路径';
    }
    btnKeilClear?.classList.add('hidden');
    setCompileStatus('浏览器模式：编译不可用', '');
} else {
    // 启动时探测工具链
    native.detectKeil?.()
        .then((info) => applyKeilInfo(info))
        .catch(() => {
            setCompileStatus('Keil 探测失败', 'is-error');
        });
}

btnCompile?.addEventListener('click', async () => {
    if (!canCompile || isCompiling) return;

    // 先刷新代码，保证编译内容与积木一致
    refresh();
    const code = codeArea.textContent || '';
    if (!code.trim() || code.startsWith('/* 生成出错')) {
        setCompileStatus('代码无效，无法编译', 'is-error');
        return;
    }

    setCompileUiBusy(true);
    setCompileStatus('Keil 编译中…', 'is-busy');
    setChipState('generating');
    setBuildLog('正在调用 Keil C251 / UV4 批编译…\n');
    lastHexPath = null;
    btnOpenHex?.classList.add('hidden');

    try {
        const result = await native.compile(code);
        setBuildLog(result?.log || result?.message || '（无日志）');

        if (result?.success) {
            lastHexPath = result.hexPath || null;
            const size = result.summary?.programSize;
            setCompileStatus(size ? `编译成功 · ${size}` : '编译成功', 'is-ok');
            setChipState('ok');
            if (lastHexPath) btnOpenHex?.classList.remove('hidden');
        } else {
            setCompileStatus(result?.message || '编译失败', 'is-error');
            setChipState('error');
            if (result?.hexPath) {
                lastHexPath = result.hexPath;
                btnOpenHex?.classList.remove('hidden');
            }
        }
    } catch (err) {
        setCompileStatus(err?.message || '编译异常', 'is-error');
        setBuildLog(String(err?.stack || err));
        setChipState('error');
    } finally {
        setCompileUiBusy(false);
        // 编译后刷新路径状态（不覆盖成功/失败文案时仅更新 title）
        try {
            const info = await native.detectKeil?.();
            if (info?.uv4 && btnCompile) btnCompile.title = `使用：${info.uv4}`;
            if (info) {
                const hasManual = info.source === 'manual';
                btnKeilClear?.classList.toggle('hidden', !hasManual);
            }
        } catch {
            /* ignore */
        }
    }
});

btnKeilPath?.addEventListener('click', async () => {
    if (!canCompile || isCompiling || !native?.chooseKeilPath) return;
    setCompileStatus('选择 Keil 路径…', 'is-busy');
    try {
        const result = await native.chooseKeilPath();
        if (result?.canceled) {
            // 取消时恢复当前探测状态
            const info = result.info || (await native.detectKeil?.());
            applyKeilInfo(info);
            return;
        }
        if (result?.info) applyKeilInfo(result.info);
        else applyKeilInfo(await native.detectKeil?.());

        if (result?.success) {
            setBuildLog(
                `已设置 Keil 路径\n${result.message || ''}\nUV4: ${result.info?.uv4 || ''}\nC251: ${result.info?.c251 || ''}\n`,
            );
        } else {
            setBuildLog(result?.message || '路径无效');
            setCompileStatus(result?.message || '路径无效', 'is-error');
        }
    } catch (err) {
        setCompileStatus(err?.message || '选择路径失败', 'is-error');
        setBuildLog(String(err?.stack || err));
    }
});

btnKeilClear?.addEventListener('click', async () => {
    if (!canCompile || isCompiling || !native?.clearKeilPath) return;
    try {
        const result = await native.clearKeilPath();
        applyKeilInfo(result?.info || (await native.detectKeil?.()));
        setBuildLog(result?.message || '已清除手动路径');
    } catch (err) {
        setCompileStatus(err?.message || '重置失败', 'is-error');
    }
});

btnOpenHex?.addEventListener('click', async () => {
    if (!lastHexPath || !native?.showItemInFolder) return;
    await native.showItemInFolder(lastHexPath);
});

btnClearLog?.addEventListener('click', () => {
    setBuildLog('');
});

// 代码区折叠/展开
const codePanel = document.getElementById('code-panel');
const codeToggle = document.getElementById('code-toggle');
codeToggle.addEventListener('click', () => {
    const collapsed = codePanel.classList.toggle('collapsed');
    codeToggle.textContent = collapsed ? '展开 ◀' : '收起 ▶';
    // Blockly 需要重新计算尺寸
    setTimeout(() => Blockly.svgResize(workspace), 250);
});

// ========== 项目保存 / 打开（.pieblock，积木 JSON，非 main.c）==========
const projectNameEl = document.getElementById('project-name');
const btnNewProject = document.getElementById('btn-new-project');
const btnOpenProject = document.getElementById('btn-open-project');
const btnSaveProject = document.getElementById('btn-save-project');
const btnSaveProjectAs = document.getElementById('btn-save-project-as');

/** @type {string|null} 当前已关联的项目文件路径（仅 Electron） */
let currentProjectPath = null;
/** 当前项目显示名 */
let currentProjectName = '未命名项目';
/** 磁盘上对应的创建时间（另存/覆盖时保留） */
let currentProjectCreatedAt = null;
/** 自上次保存后是否有未保存修改 */
let projectDirty = false;
/** 抑制加载时产生的 change 事件把 dirty 置位 */
let suppressDirty = false;

function updateProjectTitle() {
    const label = projectDirty ? `${currentProjectName} *` : currentProjectName;
    if (projectNameEl) {
        projectNameEl.textContent = label;
        projectNameEl.title = currentProjectPath
            ? currentProjectPath
            : '尚未保存到文件';
    }
    const base = 'STC32G 图形化编程';
    document.title = projectDirty ? `${label} — ${base}` : `${currentProjectName} — ${base}`;
}

function markDirty() {
    if (suppressDirty) return;
    if (!projectDirty) {
        projectDirty = true;
        updateProjectTitle();
    }
}

function markClean() {
    projectDirty = false;
    updateProjectTitle();
}

function setProjectIdentity({ name, filePath, createdAt, clean = true } = {}) {
    if (name != null) currentProjectName = name || '未命名项目';
    if (filePath !== undefined) currentProjectPath = filePath || null;
    if (createdAt !== undefined) currentProjectCreatedAt = createdAt || null;
    if (clean) markClean();
    else updateProjectTitle();
}

function serializeCurrentProject() {
    const doc = buildProjectDocument(workspace, {
        name: currentProjectName,
        createdAt: currentProjectCreatedAt || undefined,
    });
    return {
        doc,
        text: `${JSON.stringify(doc, null, 2)}\n`,
    };
}

/**
 * 若有未保存修改，询问是否继续。
 * @returns {Promise<boolean>} true 表示可以继续
 */
async function confirmDiscardIfDirty() {
    if (!projectDirty) return true;
    return window.confirm(
        `「${currentProjectName}」有未保存的修改。\n继续将丢失这些修改，是否继续？`,
    );
}

async function newProject() {
    if (!(await confirmDiscardIfDirty())) return;
    suppressDirty = true;
    try {
        loadDefaultWorkspace(workspace, Blockly);
        setProjectIdentity({
            name: '未命名项目',
            filePath: null,
            createdAt: null,
            clean: true,
        });
        refresh();
    } finally {
        suppressDirty = false;
    }
}

/**
 * @param {string} content
 * @param {{ filePath?: string|null, fallbackName?: string }} [opts]
 */
function loadProjectFromContent(content, opts = {}) {
    const parsed = parseProjectDocument(content);
    if (!parsed.ok) {
        window.alert(`无法打开项目：${parsed.message}`);
        return false;
    }
    const { doc } = parsed;
    suppressDirty = true;
    try {
        applyProjectToWorkspace(workspace, Blockly, doc);
        const name =
            (typeof doc.name === 'string' && doc.name.trim()) ||
            (opts.filePath ? nameFromPath(opts.filePath) : '') ||
            opts.fallbackName ||
            '未命名项目';
        setProjectIdentity({
            name,
            filePath: opts.filePath ?? null,
            createdAt: typeof doc.createdAt === 'string' ? doc.createdAt : null,
            clean: true,
        });
        refresh();
        return true;
    } catch (err) {
        window.alert(`加载项目失败：${err?.message || err}`);
        return false;
    } finally {
        suppressDirty = false;
    }
}

async function openProject() {
    if (!(await confirmDiscardIfDirty())) return;

    if (native?.openProject) {
        try {
            const result = await native.openProject();
            if (result?.canceled) return;
            if (result?.message && result.content == null) {
                window.alert(result.message);
                return;
            }
            loadProjectFromContent(result.content, {
                filePath: result.filePath || null,
            });
        } catch (err) {
            window.alert(`打开项目失败：${err?.message || err}`);
        }
        return;
    }

    // 浏览器降级：input[type=file]
    const picked = await pickAndReadTextFile({
        accept: `.${PROJECT_EXTENSION},application/json,.json`,
    });
    if (!picked) return;
    loadProjectFromContent(picked.content, {
        filePath: null,
        fallbackName: nameFromPath(picked.name),
    });
}

/**
 * @param {{ saveAs?: boolean }} [opts]
 */
async function saveProject(opts = {}) {
    const saveAs = Boolean(opts.saveAs);
    const { doc, text } = serializeCurrentProject();

    if (native?.saveProject) {
        try {
            const needDialog = saveAs || !currentProjectPath;
            const api = needDialog
                ? (native.saveProjectAs || native.saveProject)
                : native.saveProject;
            const result = await api({
                content: text,
                // 另存为时仍传入当前路径，供对话框默认目录；写入由 forceDialog 控制
                filePath: currentProjectPath,
                suggestedName: `${currentProjectName}.${PROJECT_EXTENSION}`,
            });
            if (result?.canceled) return false;
            if (result?.success === false) {
                window.alert(result.message || '保存失败');
                return false;
            }
            const filePath = result.filePath || currentProjectPath;
            setProjectIdentity({
                name: nameFromPath(filePath) || doc.name,
                filePath,
                createdAt: doc.createdAt,
                clean: true,
            });
            return true;
        } catch (err) {
            window.alert(`保存失败：${err?.message || err}`);
            return false;
        }
    }

    // 浏览器降级：下载 .pieblock
    const name = currentProjectName || '未命名项目';
    downloadTextFile(text, `${name}.${PROJECT_EXTENSION}`);
    setProjectIdentity({
        name,
        filePath: null,
        createdAt: doc.createdAt,
        clean: true,
    });
    return true;
}

workspace.addChangeListener((event) => {
    if (suppressDirty) return;
    if (event.type === Blockly.Events.UI) return;
    if (event.isUiEvent) return;
    // 加载/清空等批量事件结束后再标脏
    if (event.type === Blockly.Events.FINISHED_LOADING) return;
    markDirty();
});

btnNewProject?.addEventListener('click', () => {
    void newProject();
});
btnOpenProject?.addEventListener('click', () => {
    void openProject();
});
btnSaveProject?.addEventListener('click', () => {
    void saveProject({ saveAs: false });
});
btnSaveProjectAs?.addEventListener('click', () => {
    void saveProject({ saveAs: true });
});

// 快捷键：Ctrl/Cmd+N/O/S，Ctrl+Shift+S
window.addEventListener('keydown', (e) => {
    const mod = e.ctrlKey || e.metaKey;
    if (!mod) return;
    const key = e.key.toLowerCase();
    if (key === 's') {
        e.preventDefault();
        void saveProject({ saveAs: e.shiftKey });
    } else if (key === 'o') {
        e.preventDefault();
        void openProject();
    } else if (key === 'n') {
        e.preventDefault();
        void newProject();
    }
});

// 关闭页面前提示未保存（浏览器 / Electron 渲染进程）
window.addEventListener('beforeunload', (e) => {
    if (!projectDirty) return;
    e.preventDefault();
    e.returnValue = '';
});

updateProjectTitle();
refresh();

// 调试用：开发环境暴露工作区到全局对象
if (import.meta.env?.DEV) {
    window.workspace = workspace;
    window.Blockly = Blockly;
}
