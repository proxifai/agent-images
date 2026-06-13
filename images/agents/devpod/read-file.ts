#!/usr/bin/env bun
/**
 * read-file.ts — reads a single workspace file safely.
 *
 *   bun read-file.ts --path src/App.tsx
 *
 * Validates the path so it can't escape /workspace, refuses files larger
 * than 200 KB, and emits the raw file content directly on stdout (the
 * Go side passes it through to the client). Errors go to stderr +
 * exit-1; the client sees them as the exec error.
 */
import { readFile, stat } from "node:fs/promises";
import { resolve, join } from "node:path";

const ROOT = process.env.WORKSPACE ?? "/workspace";
const MAX_BYTES = 200_000;

const args = parseArgs(process.argv.slice(2));
if (!args.path) {
  process.stderr.write("read-file: --path required\n");
  process.exit(1);
}

const safeRoot = resolve(ROOT);
const abs = resolve(join(safeRoot, args.path));
if (!abs.startsWith(safeRoot + "/") && abs !== safeRoot) {
  process.stderr.write(`read-file: path escapes workspace: ${args.path}\n`);
  process.exit(1);
}

try {
  const st = await stat(abs);
  if (!st.isFile()) {
    process.stderr.write(`read-file: not a file: ${args.path}\n`);
    process.exit(1);
  }
  if (st.size > MAX_BYTES) {
    process.stderr.write(`read-file: too large (${st.size} > ${MAX_BYTES})\n`);
    process.exit(1);
  }
  const content = await readFile(abs, "utf8");
  process.stdout.write(content);
  process.exit(0);
} catch (e) {
  process.stderr.write(
    `read-file: ${e instanceof Error ? e.message : String(e)}\n`,
  );
  process.exit(1);
}

function parseArgs(argv: string[]): Record<string, string> {
  const out: Record<string, string> = {};
  for (let i = 0; i < argv.length; i++) {
    if (argv[i].startsWith("--") && i + 1 < argv.length) {
      out[argv[i].slice(2)] = argv[++i];
    }
  }
  return out;
}
