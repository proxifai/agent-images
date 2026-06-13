#!/usr/bin/env bun
/**
 * list-files.ts — walks /workspace and emits one JSON line listing
 * every file the Code tab should show. Excludes node_modules, .git,
 * dist, .vite, .proxibuild, .cache, etc. so the response stays small.
 *
 * Output (single line):
 *   { "files": [{ "path": "src/App.tsx", "size": 612 }, ...] }
 */
import { readdir, stat } from "node:fs/promises";
import { join, relative } from "node:path";

const ROOT = process.env.WORKSPACE ?? "/workspace";
const EXCLUDE = new Set([
  "node_modules",
  ".git",
  "dist",
  ".vite",
  ".cache",
  ".proxibuild",
  ".turbo",
  "drizzle",
]);
const MAX_FILES = 500;

async function walk(dir: string, out: Array<{ path: string; size: number }>) {
  if (out.length >= MAX_FILES) return;
  let entries: import("node:fs").Dirent[];
  try {
    entries = await readdir(dir, { withFileTypes: true });
  } catch {
    return;
  }
  for (const e of entries) {
    if (EXCLUDE.has(e.name)) continue;
    if (e.name.startsWith(".") && e.name !== ".env.example" && e.name !== ".gitignore") continue;
    const abs = join(dir, e.name);
    if (e.isDirectory()) {
      await walk(abs, out);
    } else if (e.isFile()) {
      try {
        const st = await stat(abs);
        out.push({ path: relative(ROOT, abs), size: st.size });
        if (out.length >= MAX_FILES) return;
      } catch {
        /* ignore unreadable */
      }
    }
  }
}

try {
  const files: Array<{ path: string; size: number }> = [];
  await walk(ROOT, files);
  files.sort((a, b) => a.path.localeCompare(b.path));
  process.stdout.write(JSON.stringify({ files }) + "\n");
  process.exit(0);
} catch (e) {
  process.stderr.write(`list-files: ${e instanceof Error ? e.message : String(e)}\n`);
  process.stdout.write(JSON.stringify({ files: [] }) + "\n");
  process.exit(1);
}
