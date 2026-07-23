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
    grid: { spacing: 20, length: 1, colour: '#ccc', snap: true },
    zoom: { controls: true, wheel: true, startScale: 0.9 },
    trashcan: true,
    move: { scrollbars: true, drag: true, wheel: true },
});

// 2. 默认放置“初始化区”与“主循环区”两个不可删除容器，上下连接
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

function refresh() {
    try {
        codeArea.textContent = generateC(workspace);
    } catch (err) {
        codeArea.textContent = '/* 生成出错: ' + err.message + ' */';
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

// 代码区折叠/展开
const codePanel = document.getElementById('code-panel');
const codeToggle = document.getElementById('code-toggle');
codeToggle.addEventListener('click', () => {
    const collapsed = codePanel.classList.toggle('collapsed');
    codeToggle.textContent = collapsed ? '展开代码 ◀' : '收起代码 ▶';
    // Blockly 需要重新计算尺寸
    setTimeout(() => Blockly.svgResize(workspace), 260);
});

refresh();

// 调试用：开发环境暴露工作区到全局对象
if (import.meta.env?.DEV) {
    window.workspace = workspace;
    window.Blockly = Blockly;
}
