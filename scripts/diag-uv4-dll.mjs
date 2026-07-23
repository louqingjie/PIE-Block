/**
 * 定位 bundled UV4 的 0xC0000135（缺 DLL）原因。
 */
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const root = path.join(path.dirname(fileURLToPath(import.meta.url)), '..');
const uv4Dir = path.join(root, 'vendor', 'keil-toolchain', 'UV4');
const uv4 = path.join(uv4Dir, 'UV4.exe');
const sysUv4Dir = path.join(process.env.LOCALAPPDATA || '', 'Keil_v5', 'UV4');
const proj = path.join(root, 'stc32g', 'Projects', '0000.培训模板', 'MDK', 'Project_Template.uvproj');
const log = path.join(root, 'stc32g', 'Projects', '0000.培训模板', 'MDK', 'diag_dll.log');

console.log('bundled UV4 exists', fs.existsSync(uv4));
console.log('system UV4 dir exists', fs.existsSync(sysUv4Dir));

// 1) 对比系统 UV4 根目录文件，看是否有额外 DLL/manifest
const list = (dir) =>
    fs.existsSync(dir)
        ? fs
            .readdirSync(dir)
            .filter((n) => {
                try {
                    return fs.statSync(path.join(dir, n)).isFile();
                } catch {
                    return false;
                }
            })
            .map((n) => n.toLowerCase())
            .sort()
        : [];

const src = list(sysUv4Dir);
const dst = list(uv4Dir);
const missing = src.filter((n) => !dst.includes(n));
console.log('missing files from system UV4 root:', missing);

// 2) 用 where / 尝试运行并看 exit
function tryRun(label, opts) {
    try {
        if (fs.existsSync(log)) fs.unlinkSync(log);
    } catch {
        /* ignore */
    }
    const r = spawnSync(uv4, ['-b', proj, '-o', log], {
        windowsHide: true,
        timeout: 30000,
        encoding: 'utf8',
        ...opts,
    });
    console.log(
        label,
        'status=',
        r.status,
        'signal=',
        r.signal,
        'error=',
        r.error?.message || null,
        'log=',
        fs.existsSync(log),
    );
    if (fs.existsSync(log)) {
        console.log(fs.readFileSync(log, 'utf8').slice(0, 400));
    }
}

tryRun('cwd=project PATH=default', { cwd: path.dirname(proj) });
tryRun('cwd=UV4 PATH=default', { cwd: uv4Dir });
tryRun('cwd=project PATH=UV4', {
    cwd: path.dirname(proj),
    env: { ...process.env, PATH: `${uv4Dir};${process.env.PATH || ''}` },
});

// 3) 若系统 UV4 能跑，对比两者依赖文件大小
const sysUv4 = path.join(sysUv4Dir, 'UV4.exe');
if (fs.existsSync(sysUv4)) {
    const a = fs.statSync(sysUv4).size;
    const b = fs.statSync(uv4).size;
    console.log('UV4.exe size system', a, 'bundled', b, 'same', a === b);
}

// 4) 尝试用 cmd start 捕获？ 检查 SxS 清单
const manifest = path.join(uv4Dir, 'Microsoft.VC80.CRT.manifest');
if (fs.existsSync(manifest)) {
    console.log('VC80 manifest:\n', fs.readFileSync(manifest, 'utf8'));
}

// 5) 检查常见依赖是否在 UV4 旁
for (const name of [
    'msvcr80.dll',
    'msvcr100.dll',
    'gdiplus.dll',
    'UV4.dll',
    'UvCC.dll',
    'UvEdit.dll',
    'UVAC.dll',
    'xerces-c_3_0.dll',
    'dcomutil_libFNP.dll',
    'msvcp80.dll',
    'msvcm80.dll',
]) {
    console.log(name, fs.existsSync(path.join(uv4Dir, name)) ? 'OK' : 'MISSING');
}
