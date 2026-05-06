import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

// https://vitejs.dev/config/
export default defineConfig({
  plugins: [
    vue()
  ],
  base: './', // Ensures assets load correctly on GitHub Pages
  build: {
    outDir: '../docs',
    emptyOutDir: false // IMPORTANT: Keeps your DMG and appcast.xml safe!
  }
})
