import { app, BrowserWindow, shell, ipcMain, dialog } from 'electron';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { compileWithKeil, detectKeil } from './keil-build.js';

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
            sandbox: false, // preload 为 CommonJS；保持 contextIsolation
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

    // 外链用系统浏览器打开
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

// 未捕获异常时避免静默退出，便于排查编译相关问题
process.on('uncaughtException', (err) => {
    console.error('[main] uncaughtException', err);
    if (mainWindow && !mainWindow.isDestroyed()) {
        dialog.showErrorBox('应用异常', err?.message || String(err));
    }
});
