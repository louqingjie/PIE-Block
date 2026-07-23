import * as Blockly from 'blockly';
import 'blockly/blocks';                 // 注册 Blockly 内置积木（if/while/数学/逻辑…）
import { javascriptGenerator } from 'blockly/javascript';

import './blocks/index.js';               // 注册自定义积木
import './generators/index.js';           // 注册 C 代码生成器
import { toolbox } from './toolbox.js';
import { generateC } from './generators/c_generator.js';
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
const setupBlock = Blockly.serialization.blocks.append(
    { type: 'stc_setup', x: 20, y: 20 }, workspace,
);
const loopBlock = Blockly.serialization.blocks.append(
    { type: 'stc_loop', x: 20, y: 160 }, workspace,
);
// 直接连接 API 确保两个容器堆叠在一起
loopBlock.previousConnection.connect(setupBlock.nextConnection);

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
}

if (!canCompile) {
    // 浏览器预览模式：无 Node/Keil，禁用编译
    if (btnCompile) {
        btnCompile.disabled = true;
        btnCompile.title = '请在 Electron 桌面端使用 Keil 编译';
    }
    setCompileStatus('浏览器模式：编译不可用', '');
} else {
    // 启动时探测工具链
    native.detectKeil?.().then((info) => {
        if (!info?.found) {
            setCompileStatus('未检测到 Keil C251', 'is-error');
            if (btnCompile) btnCompile.title = info?.message || '未安装 Keil C251';
        } else if (!info.projectReady) {
            setCompileStatus('工程模板缺失', 'is-error');
        } else {
            setCompileStatus(
                info.c251Version ? `C251 ${info.c251Version}` : 'Keil 已就绪',
                'is-ok',
            );
        }
    }).catch(() => {
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

refresh();

// 调试用：开发环境暴露工作区到全局对象
if (import.meta.env?.DEV) {
    window.workspace = workspace;
    window.Blockly = Blockly;
}
