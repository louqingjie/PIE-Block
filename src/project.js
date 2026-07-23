/**
 * 图形化项目文件：序列化 / 反序列化 Blockly 工作区。
 * 扩展名 .pieblock，内容为 JSON（积木状态，不是 main.c）。
 */
import * as Blockly from 'blockly';

export const PROJECT_FORMAT = 'pie-block-project';
export const PROJECT_VERSION = 1;
export const PROJECT_EXTENSION = 'pieblock';
export const PROJECT_FILTER_NAME = 'STC32G 图形化项目';

/**
 * @param {import('blockly').WorkspaceSvg} workspace
 * @param {{ name?: string, createdAt?: string }} [meta]
 */
export function buildProjectDocument(workspace, meta = {}) {
    const now = new Date().toISOString();
    return {
        format: PROJECT_FORMAT,
        version: PROJECT_VERSION,
        name: meta.name || '未命名项目',
        createdAt: meta.createdAt || now,
        updatedAt: now,
        app: {
            target: 'STC32G12K128',
            product: 'pie-block',
        },
        // Blockly 官方工作区序列化（含积木、变量、位置等）
        workspace: Blockly.serialization.workspaces.save(workspace),
    };
}

/**
 * @param {unknown} data
 * @returns {{ ok: true, doc: object } | { ok: false, message: string }}
 */
export function parseProjectDocument(data) {
    if (data == null) {
        return { ok: false, message: '项目文件为空' };
    }
    let doc = data;
    if (typeof data === 'string') {
        try {
            doc = JSON.parse(data);
        } catch {
            return { ok: false, message: '项目文件不是有效的 JSON' };
        }
    }
    if (typeof doc !== 'object' || Array.isArray(doc)) {
        return { ok: false, message: '项目文件格式无效' };
    }
    if (doc.format !== PROJECT_FORMAT) {
        return {
            ok: false,
            message: `无法识别的项目格式（期望 ${PROJECT_FORMAT}）`,
        };
    }
    if (doc.version == null || Number(doc.version) > PROJECT_VERSION) {
        return {
            ok: false,
            message: `不支持的项目版本：${doc.version ?? '未知'}（当前支持 ≤ ${PROJECT_VERSION}）`,
        };
    }
    if (!doc.workspace || typeof doc.workspace !== 'object') {
        return { ok: false, message: '项目文件缺少工作区数据' };
    }
    return { ok: true, doc };
}

/**
 * 从文件名推导项目显示名（去掉扩展名）。
 * @param {string} filePath
 */
export function nameFromPath(filePath) {
    if (!filePath || typeof filePath !== 'string') return '未命名项目';
    const base = filePath.replace(/^.*[/\\]/, '');
    return base.replace(/\.pieblock$/i, '') || '未命名项目';
}

/**
 * 确保初始化区 / 主循环区存在且不可删除。
 * 注意：setup/loop 连接后 loop 不是 top block，必须用 getAllBlocks 查找。
 * @param {import('blockly').WorkspaceSvg} workspace
 * @param {typeof import('blockly')} Blockly
 */
export function ensureCoreBlocks(workspace, Blockly) {
    const all = workspace.getAllBlocks(false);
    let setup = all.find((b) => b.type === 'stc_setup') || null;
    let loop = all.find((b) => b.type === 'stc_loop') || null;

    if (!setup) {
        setup = Blockly.serialization.blocks.append(
            { type: 'stc_setup', x: 20, y: 20 },
            workspace,
        );
    }
    if (!loop) {
        loop = Blockly.serialization.blocks.append(
            { type: 'stc_loop', x: 20, y: 160 },
            workspace,
        );
    }

    setup.setDeletable(false);
    setup.setMovable(false);
    loop.setDeletable(false);
    loop.setMovable(false);

    // 若尚未连接且两端空闲，则上下接好
    if (
        setup.nextConnection &&
        loop.previousConnection &&
        !setup.nextConnection.isConnected() &&
        !loop.previousConnection.isConnected()
    ) {
        loop.previousConnection.connect(setup.nextConnection);
    }
}

/**
 * 加载空白默认工程（仅初始化区 + 主循环区）。
 * @param {import('blockly').WorkspaceSvg} workspace
 * @param {typeof import('blockly')} Blockly
 */
export function loadDefaultWorkspace(workspace, Blockly) {
    workspace.clear();
    const setupBlock = Blockly.serialization.blocks.append(
        { type: 'stc_setup', x: 20, y: 20 },
        workspace,
    );
    const loopBlock = Blockly.serialization.blocks.append(
        { type: 'stc_loop', x: 20, y: 160 },
        workspace,
    );
    loopBlock.previousConnection.connect(setupBlock.nextConnection);
}

/**
 * 将项目文档载入工作区。
 * @param {import('blockly').WorkspaceSvg} workspace
 * @param {typeof import('blockly')} Blockly
 * @param {object} doc
 */
export function applyProjectToWorkspace(workspace, Blockly, doc) {
    workspace.clear();
    Blockly.serialization.workspaces.load(doc.workspace, workspace, {
        recordUndo: false,
    });
    ensureCoreBlocks(workspace, Blockly);
}

/**
 * 浏览器端：触发下载项目文件。
 * @param {string} jsonText
 * @param {string} filename
 */
export function downloadTextFile(jsonText, filename) {
    const blob = new Blob([jsonText], { type: 'application/json;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = filename.endsWith(`.${PROJECT_EXTENSION}`)
        ? filename
        : `${filename}.${PROJECT_EXTENSION}`;
    a.click();
    URL.revokeObjectURL(url);
}

/**
 * 浏览器端：选择并读取一个文本文件。
 * @param {{ accept?: string }} [opts]
 * @returns {Promise<{ name: string, content: string } | null>}
 */
export function pickAndReadTextFile(opts = {}) {
    return new Promise((resolve) => {
        const input = document.createElement('input');
        input.type = 'file';
        input.accept = opts.accept || `.${PROJECT_EXTENSION},application/json`;
        input.style.display = 'none';
        const cleanup = () => {
            input.remove();
        };
        input.addEventListener('change', async () => {
            const file = input.files?.[0];
            if (!file) {
                cleanup();
                resolve(null);
                return;
            }
            try {
                const content = await file.text();
                resolve({ name: file.name, content });
            } catch (err) {
                resolve(null);
            } finally {
                cleanup();
            }
        });
        // 用户取消时部分浏览器不触发 change；短时后若仍无文件则静默（无法可靠检测取消）
        document.body.appendChild(input);
        input.click();
    });
}
