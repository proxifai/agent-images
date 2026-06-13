import path from "node:path";
import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";
import { proxibuildBabelPlugin, proxibuildOverlayPlugin } from "./proxibuild.vite";

const WORKSPACE = process.env.WORKSPACE ?? process.cwd();

export default defineConfig({
  plugins: [
    react({
      babel: {
        plugins: [
          // Tags every host JSX element with data-pb-id=<file:line:col>
          // so the overlay's click handler can identify the element to
          // edit. Strips the workspace root from the filename so the
          // ID stays portable across pod restarts.
          [proxibuildBabelPlugin, { workspace: WORKSPACE }],
        ],
      },
    }),
    tailwindcss(),
    // Injects the iframe overlay script that drives Visual Edits.
    proxibuildOverlayPlugin(),
  ],
  resolve: {
    // `@/foo` → `<workspace>/src/foo` so the shadcn-style imports work
    // out of the box: `import { Button } from "@/components/ui/button"`.
    alias: {
      "@": path.resolve(WORKSPACE, "src"),
    },
  },
  server: {
    host: "0.0.0.0",
    port: 5173,
    strictPort: true,
    hmr: {
      // Proxifai serves the dev pod at <id>-5173.proxif.ai via the
      // port-proxy; HMR websocket needs to know the public host so the
      // browser connects back through the same hostname.
      clientPort: 443,
    },
    // The flat-subdomain routing layer terminates TLS and forwards plain
    // HTTP to the pod; vite needs to trust the forwarded Host header.
    allowedHosts: true,
  },
});
