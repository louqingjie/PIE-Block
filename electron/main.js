import { app, BrowserWindow, shell, ipcMain, dialog } from 'electron';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
    compileWithKeil,
    detectKeil,
    applyKeilSelection,
    clearKeilConfig,
    loadKeilConfig,
} from './keil-build.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const isDev = !app.isPackaged;

/** @type {BrowserWindow | null} */
let mainWindow = null;

/** 避免并发多次 UV4 批编译 */
let compiling = false;

function createWindow() {
    mainWindow = new BrowserWindow({
        width: 1280,
        height: 800,
        minWidth: 960,
        minHeight: 640,
        title: 'STC32G 图形化编程',
        show: false,
        autoHideMenuBar: true,
        webPreferences: {
            preload: path.join(__dirname, 'preload.cjs'),
            contextIsolation: true,
            nodeIntegration: false,
            sandbox: false,
        },
    });

    mainWindow.once('ready-to-show', () => {
        mainWindow?.show();
    });

    if (isDev) {
        const devUrl = process.env.VITE_DEV_SERVER_URL || 'http://localhost:5173';
        mainWindow.loadURL(devUrl);
        mainWindow.webContents.openDevTools({ mode: 'detach' });
    } else {
        mainWindow.loadFile(path.join(__dirname, '../dist/index.html'));
    }

    mainWindow.webContents.setWindowOpenHandler(({ url }) => {
        shell.openExternal(url);
        return { action: 'deny' };
    });

    mainWindow.on('closed', () => {
        mainWindow = null;
    });
}

function registerIpc() {
    ipcMain.handle('keil:detect', async () => {
        try {
            return await detectKeil();
        } catch (err) {
            return {
                found: false,
                projectReady: false,
                message: err?.message || String(err),
            };
        }
    });

    ipcMain.handle('keil:compile', async (_event, code) => {
        if (compiling) {
            return {
                success: false,
                stage: 'busy',
                message: '已有编译任务进行中，请稍候。',
                log: '',
                hexPath: null,
            };
        }
        compiling = true;
        try {
            return await compileWithKeil(typeof code === 'string' ? code : '');
        } catch (err) {
            return {
                success: false,
                stage: 'exception',
                message: err?.message || String(err),
                log: '',
                hexPath: null,
            };
        } finally {
            compiling = false;
        }
    });

    /** 打开对话框选择 Keil 目录或 UV4.exe，并保存配置 */
    ipcMain.handle('keil:choosePath', async () => {
        const win = BrowserWindow.getFocusedWindow() || mainWindow;
        const cfg = loadKeilConfig();
        const defaultPath =
            cfg.customRoot ||
            cfg.customUv4 ||
            path.join(process.env.LOCALAPPDATA || 'C:\\', 'Keil_v5');

        // Windows 不能同时 openFile + openDirectory，先让用户选类型
        const pick = await dialog.showMessageBox(win ?? undefined, {
            type: 'question',
            title: '选择 Keil 路径',
            message: '请选择要指定的路径类型',
            detail:
                '推荐选择 UV4.exe（…\\Keil_v5\\UV4\\UV4.exe），\n也可选择整个 Keil 安装根目录（…\\Keil_v5）。',
            buttons: ['选择 UV4.exe', '选择安装目录', '取消'],
            defaultId: 0,
            cancelId: 2,
            noLink: true,
        });

        if (pick.response === 2) {
            return {
                canceled: true,
                success: false,
                message: '已取消选择',
                info: await detectKeil(),
            };
        }

        const chooseFile = pick.response === 0;
        const result = await dialog.showOpenDialog(win ?? undefined, {
            title: chooseFile ? '选择 UV4.exe 或 C251.EXE' : '选择 Keil 安装根目录',
            defaultPath,
            properties: chooseFile ? ['openFile'] : ['openDirectory'],
            filters: chooseFile
                ? [
                    { name: '可执行文件', extensions: ['exe'] },
                    { name: '所有文件', extensions: ['*'] },
                ]
                : undefined,
        });

        if (result.canceled || !result.filePaths?.length) {
            return {
                canceled: true,
                success: false,
                message: '已取消选择',
                info: await detectKeil(),
            };
        }

        try {
            const applied = await applyKeilSelection(result.filePaths[0]);
            return {
                canceled: false,
                ...applied,
            };
        } catch (err) {
            return {
                canceled: false,
                success: false,
                message: err?.message || String(err),
                info: await detectKeil(),
            };
        }
    });

    /** 清除手动路径，恢复自动探测 */
    ipcMain.handle('keil:clearPath', async () => {
        try {
            clearKeilConfig();
            const info = await detectKeil();
            return {
                success: true,
                message: '已清除手动路径，恢复自动探测',
                info,
            };
        } catch (err) {
            return {
                success: false,
                message: err?.message || String(err),
                info: null,
            };
        }
    });

    ipcMain.handle('shell:showItemInFolder', async (_event, filePath) => {
        if (typeof filePath !== 'string' || !filePath) {
            return { ok: false, message: '无效路径' };
        }
        try {
            shell.showItemInFolder(filePath);
            return { ok: true };
        } catch (err) {
            return { ok: false, message: err?.message || String(err) };
        }
    });

    ipcMain.handle('shell:openPath', async (_event, targetPath) => {
        if (typeof targetPath !== 'string' || !targetPath) {
            return { ok: false, message: '无效路径' };
        }
        try {
            const errMsg = await shell.openPath(targetPath);
            if (errMsg) return { ok: false, message: errMsg };
            return { ok: true };
        } catch (err) {
            return { ok: false, message: err?.message || String(err) };
        }
    });
}

app.whenReady().then(() => {
    registerIpc();
    createWindow();

    app.on('activate', () => {
        if (BrowserWindow.getAllWindows().length === 0) {
            createWindow();
        }
    });
});

app.on('window-all-closed', () => {
    if (process.platform !== 'darwin') {
        app.quit();
    }
});

process.on('uncaughtException', (err) => {
    console.error('[main] uncaughtException', err);
    if (mainWindow && !mainWindow.isDestroyed()) {
        dialog.showErrorBox('应用异常', err?.message || String(err));
    }
});
