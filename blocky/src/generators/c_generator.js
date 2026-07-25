import { javascriptGenerator } from 'blockly/javascript';

// 统一 4 空格缩进，保证生成代码层次与 C 语义一致
javascriptGenerator.INDENT = '    ';

const MAIN_TEMPLATE = `#include "main.h"

/* ===== 全局变量（自动生成）===== */
%VARIABLES%

/* ===== 主函数 ===== */
void main(void)
{
    Board_Init();

    /* ===== 初始化区 ===== */
%SETUP%

    /* ===== 主循环 ===== */
    while (1)
    {
%LOOP%
    }
}
`;

// 顶层遍历，提取 setup / loop 两段，并收集全局变量声明
// 注意：stc_loop 连接在 stc_setup 下方（next 堆叠），不再是顶层块。
// 用 statementToCode 而非 blockToCode，避免自动递归 next 链导致主循环代码混入初始化区。
export function generateC(workspace) {
    const gen = javascriptGenerator;
    gen.init(workspace);

    let setupCode = '';
    let loopCode = '';

    for (const block of workspace.getTopBlocks(true)) {
        if (block.type === 'stc_setup') {
            setupCode = norm(gen.statementToCode(block, 'STACK'));
            // 沿 next 连接链查找主循环区
            let next = block.getNextBlock();
            while (next) {
                if (next.type === 'stc_loop') {
                    loopCode = norm(gen.statementToCode(next, 'STACK'));
                    break;
                }
                next = next.getNextBlock();
            }
        } else if (block.type === 'stc_loop') {
            // 兼容：若主循环区未连接到初始化区（独立浮动）
            loopCode = norm(gen.statementToCode(block, 'STACK'));
        }
    }

    const variables = Object.values(gen.definitions_ || {})
        .filter(Boolean).join('\n') || '/* 无 */';

    if (typeof gen.finish === 'function') gen.finish();

    return MAIN_TEMPLATE
        .replace('%VARIABLES%', variables)
        .replace('%SETUP%', setupCode.trim() ? setupCode : '    /* 无 */')
        .replace('%LOOP%', loopCode.trim() ? indent(loopCode, gen.INDENT) : '        /* 无 */');
}

// 统一规范化生成器返回值（可能是 [code, order] 数组）
function norm(result) {
    const code = Array.isArray(result) ? result[0] : result;
    return (code || '').replace(/\n$/, '');
}

function indent(text, prefix) {
    return text.split('\n').map((line) => (line ? prefix + line : line)).join('\n');
}
