const { contextBridge, ipcRenderer } = require('electron');

/**
 * 渲染进程安全 API：仅暴露编译相关能力，不放开任意 Node/fs。
 */
contextBridge.exposeInMainWorld('pieNative', {
    /** 探测本机 Keil C251 / 工程模板是否可用。 */
    detectKeil: () => ipcRenderer.invoke('keil:detect'),

    /** 用 Keil C251 编译生成的 C 代码。 */
    compile: (code) => ipcRenderer.invoke('keil:compile', code),

    /** 打开对话框选择 Keil 安装目录或 UV4.exe。 */
    chooseKeilPath: () => ipcRenderer.invoke('keil:choosePath'),

    /** 清除手动路径，恢复自动探测。 */
    clearKeilPath: () => ipcRenderer.invoke('keil:clearPath'),

    /** 在资源管理器中显示文件。 */
    showItemInFolder: (filePath) => ipcRenderer.invoke('shell:showItemInFolder', filePath),

    /** 用系统默认程序打开路径。 */
    openPath: (targetPath) => ipcRenderer.invoke('shell:openPath', targetPath),

    /** 是否运行在 Electron 桌面端 */
    isElectron: true,
});
