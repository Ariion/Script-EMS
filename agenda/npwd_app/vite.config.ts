import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import federation from '@originjs/vite-plugin-federation';

export default defineConfig({
  plugins: [
    react(),
    federation({
      name: 'agenda',
      filename: 'remoteEntry.js',
      exposes: {
        './config': './src/config',
      },
      shared: {
        react: { singleton: true, requiredVersion: false },
        'react-dom': { singleton: true, requiredVersion: false },
        'react-router-dom': { singleton: true, requiredVersion: false },
      },
    }),
  ],
  build: {
    target: 'esnext',
    outDir: '../html/npwd',
    emptyOutDir: true,
    assetsDir: '',
    minify: true,
    rollupOptions: {
      input: 'src/config.ts',
      output: {
        entryFileNames: '[name].js',
        chunkFileNames: '[name].js',
      },
    },
  },
  base: 'https://agenda/html/npwd/',
});
