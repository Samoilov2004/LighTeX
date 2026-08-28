import { defineConfig } from "vitest/config";
import react from "@vitejs/plugin-react";

export default defineConfig({
  plugins: [react()],
  clearScreen: false,
  server: {
    port: 1420,
    strictPort: true,
  },
  envPrefix: ["VITE_", "TAURI_ENV_*"],
  build: {
    target: "safari13",
    sourcemap: true,
    chunkSizeWarningLimit: 900,
    rollupOptions: {
      output: {
        manualChunks(id) {
          if (id.includes("pdfjs-dist")) return "pdf-vendor";
          if (id.includes("@codemirror") || id.includes("@lezer")) return "editor-vendor";
          if (id.includes("@dnd-kit")) return "drag-vendor";
          if (id.includes("/react/") || id.includes("/react-dom/") || id.includes("/zustand/")) return "react-vendor";
          return undefined;
        },
      },
    },
  },
  worker: {
    format: "es",
  },
  test: {
    environment: "jsdom",
    setupFiles: ["./src/test/setup.ts"],
    restoreMocks: true,
  },
});
