const { contextBridge, ipcRenderer } = require('electron');

/**
 * 渲染进程安全 API：仅暴露编译相关能力，不放开任意 Node/fs。
 */
contextBridge.exposeInMainWorld('pieNative', {
    /**
     * 探测本机 Keil C251 / 工程模板是否可用。
     * @returns {Promise<object>}
     */
    detectKeil: () => ipcRenderer.invoke('keil:detect'),

    /**
     * 用 Keil C251 编译生成的 C 代码。
     * @param {string} code
     * @returns {Promise<object>}
     */
    compile: (code) => ipcRenderer.invoke('keil:compile', code),

    /**
     * 在资源管理器中显示文件。
     * @param {string} filePath
     * @returns {Promise<{ok:boolean,message?:string}>}
     */
    showItemInFolder: (filePath) => ipcRenderer.invoke('shell:showItemInFolder', filePath),

    /**
     * 用系统默认程序打开路径（如 hex / 日志）。
     * @param {string} targetPath
     * @returns {Promise<{ok:boolean,message?:string}>}
     */
    openPath: (targetPath) => ipcRenderer.invoke('shell:openPath', targetPath),

    /** 是否运行在 Electron 桌面端 */
    isElectron: true,
});
