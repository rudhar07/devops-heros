import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// Standard Vite config; `vite build` outputs static files to dist/
export default defineConfig({
  plugins: [react()],
});
