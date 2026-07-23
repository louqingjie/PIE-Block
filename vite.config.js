import { defineConfig } from 'vite';

export default defineConfig({
    // 相对路径，便于 Electron 从 file:// 加载 dist
    base: './',
    server: {
        // 桌面开发由 Electron 打开窗口，避免再弹浏览器
        open: false,
        port: 5173,
        strictPort: true,
    },
    build: {
        outDir: 'dist',
        emptyOutDir: true,
    },
});
