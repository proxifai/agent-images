#!/usr/bin/env bun
/**
 * ProxiBuild in-pod agent CLI.
 *
 * Invoked by proxifai's build.Service.dispatchPrompt via `kubectl exec`
 * as: pfai-build-agent "<user prompt>". Emits one NDJSON event per
 * stdout line. Stderr is reserved for diagnostics.
 *
 * Event shape (matches internal/build.agentEvent):
 *   { "role": "user"|"assistant"|"tool"|"system",
 *     "event_type": "message"|"thought"|"file_write"|"shell_run"|"tool_use"|...,
 *     "content": string,
 *     "token_usage": { input_tokens, output_tokens, total_tokens } }
 *
 * The proxifai service handles persistence + SSE fanout; this script
 * only emits.
 */
import { readFile, writeFile, mkdir, readdir, stat } from "node:fs/promises";
import { existsSync } from "node:fs";
import { dirname, join, relative, resolve } from "node:path";

const WORKSPACE = process.env.WORKSPACE ?? "/workspace";
const HISTORY_DIR = join(WORKSPACE, ".proxibuild");
const HISTORY_PATH = join(HISTORY_DIR, "history.jsonl");
const MODEL = process.env.BUILD_AGENT_MODEL ?? "claude-sonnet-4-6";
const MAX_FILE_BYTES = 80_000; // safety against pulling in a huge bundle

// File globs we include in the model's context. Intentionally narrow —
// the agent re-reads on every turn so the prompt stays small.
const INCLUDE_PATHS = [
  "src/App.tsx",
  "src/main.tsx",
  "src/index.css",
  "src/lib/utils.ts",
  "src/db/schema.ts",
  "src/db/index.ts",
  "index.html",
  "package.json",
  "components.json",
  "tailwind.config.ts",
  "vite.config.ts",
  "drizzle.config.ts",
];

function emit(evt: {
  role: string;
  event_type?: string;
  content: string;
  token_usage?: Record<string, number>;
}) {
  process.stdout.write(JSON.stringify(evt) + "\n");
}

function err(msg: string) {
  process.stderr.write(msg + "\n");
}

async function readWorkspaceFile(rel: string): Promise<string | null> {
  const abs = join(WORKSPACE, rel);
  if (!existsSync(abs)) return null;
  try {
    const st = await stat(abs);
    if (!st.isFile()) return null;
    if (st.size > MAX_FILE_BYTES) {
      return `<file too large: ${st.size} bytes — agent will not see contents>`;
    }
    return await readFile(abs, "utf8");
  } catch (e) {
    err(`read ${rel}: ${e}`);
    return null;
  }
}

async function listSourceFiles(): Promise<string[]> {
  const root = join(WORKSPACE, "src");
  if (!existsSync(root)) return [];
  const out: string[] = [];
  async function walk(dir: string) {
    const entries = await readdir(dir, { withFileTypes: true });
    for (const e of entries) {
      const abs = join(dir, e.name);
      if (e.isDirectory()) await walk(abs);
      else out.push(relative(WORKSPACE, abs));
    }
  }
  await walk(root);
  return out;
}

/** Apply the LLM's proposed file edits. Refuses paths outside WORKSPACE
 *  and refuses to overwrite the lock/config files we deliberately gate. */
async function applyEdits(edits: Record<string, string>): Promise<string[]> {
  const denylist = ["package-lock.json", "bun.lockb", "yarn.lock", "pnpm-lock.yaml", ".env"];
  const written: string[] = [];
  for (const [path, content] of Object.entries(edits)) {
    const safe = resolve(WORKSPACE, path);
    if (!safe.startsWith(WORKSPACE + "/")) {
      emit({ role: "system", event_type: "message", content: `Skipped path outside workspace: ${path}` });
      continue;
    }
    if (denylist.some((d) => path.endsWith(d))) {
      emit({ role: "system", event_type: "message", content: `Refused to write denylisted path: ${path}` });
      continue;
    }
    try {
      await mkdir(dirname(safe), { recursive: true });
      await writeFile(safe, content, "utf8");
      emit({ role: "assistant", event_type: "file_write", content: path });
      written.push(path);
    } catch (e) {
      emit({ role: "system", event_type: "message", content: `Failed to write ${path}: ${e}` });
    }
  }
  return written;
}

interface AgentTurn {
  user: string;
  thoughts?: string;
  message?: string;
  files?: string[]; // paths written
}

async function appendHistory(turn: AgentTurn) {
  try {
    await mkdir(HISTORY_DIR, { recursive: true });
    const line = JSON.stringify({ ts: new Date().toISOString(), ...turn });
    const cur = existsSync(HISTORY_PATH) ? await readFile(HISTORY_PATH, "utf8") : "";
    await writeFile(HISTORY_PATH, cur + line + "\n", "utf8");
  } catch (e) {
    err(`history: ${e}`);
  }
}

async function loadHistoryTail(maxTurns = 6): Promise<AgentTurn[]> {
  if (!existsSync(HISTORY_PATH)) return [];
  try {
    const txt = await readFile(HISTORY_PATH, "utf8");
    const lines = txt.split("\n").filter(Boolean);
    return lines
      .slice(-maxTurns)
      .map((l) => {
        try {
          return JSON.parse(l) as AgentTurn;
        } catch {
          return null;
        }
      })
      .filter((t): t is AgentTurn => t !== null);
  } catch (e) {
    err(`history load: ${e}`);
    return [];
  }
}

/** Emit a stream_chunk event with a raw text delta. Ephemeral on the
 *  backend — the chat renders a live bubble that accumulates these. */
function emitStreamChunk(text: string) {
  if (!text) return;
  emit({ role: "assistant", event_type: "stream_chunk", content: text });
}

/** Call the configured LLM with streaming enabled. Emits stream_chunk
 *  events as text arrives so the chat shows progress in real time, and
 *  returns the parsed structured response after the stream completes. */
async function callLLM(prompt: string, ctxFiles: Record<string, string | null>, history: AgentTurn[]): Promise<{
  thoughts: string;
  message: string;
  edits: Record<string, string>;
  usage?: { input_tokens: number; output_tokens: number };
}> {
  const system = [
    "You are ProxiBuild, an AI agent that helps users iteratively build a small React+Vite+TypeScript+Tailwind app.",
    "The user's app lives in /workspace inside a long-lived dev container; vite is running and HMR fires on every file change.",
    "Respond with STRICT JSON ONLY, no markdown fences, matching this shape:",
    '{ "thoughts": "one short sentence of reasoning", "message": "human-friendly summary of what you changed", "edits": { "<relative-path>": "<full new file contents>" } }',
    "Rules:",
    "- Always return the FULL contents of any file you change. Never return partial diffs.",
    "- Keep edits minimal — only touch what the user asked about.",
    "- Don't modify package.json, vite.config.ts, tsconfig.json, tailwind.config.ts, components.json unless absolutely required.",
    "- The app entry is src/App.tsx. Add new components under src/components/.",
    "- If the request is unclear or impossible, set edits to {} and explain in 'message'.",
    "",
    "Design system — shadcn/ui is pre-installed (Tailwind v4 + tokens in src/index.css). Use it first:",
    "- Path alias `@` resolves to /src. Import like:  import { Button } from \"@/components/ui/button\";",
    "- Pre-installed primitives (do not re-create): Button, Card (+CardHeader/Title/Description/Content/Footer), Input, Label, Badge, Separator, Dialog (+DialogTrigger/Content/Header/Title/Description/Footer/Close). Files live in src/components/ui/.",
    "- More shadcn components can be added by writing a new file under src/components/ui/<name>.tsx with the canonical shadcn implementation. Make sure the radix dep is in package.json before importing.",
    "- Style with Tailwind utilities backed by the design tokens: bg-background, text-foreground, bg-card, text-card-foreground, bg-primary, text-primary-foreground, bg-secondary, bg-muted, text-muted-foreground, bg-accent, border-border, ring-ring, bg-destructive. Avoid raw zinc-/gray-/etc. classes — use the tokens so theme switches work.",
    "- Use lucide-react for icons (already a dep). Icons sized via [&_svg]:size-X classes on the parent are the shadcn idiom.",
    "- Use cn() from @/lib/utils for conditional class merging.",
    "",
    "Database (sqlite via drizzle-orm):",
    "- Schema lives in src/db/schema.ts; the drizzle client + connection are in src/db/index.ts.",
    "- DATABASE_URL points at /workspace/data.db (bun:sqlite); the entrypoint runs `bun run db:push` on every start so any schema you write becomes a real table immediately.",
    "- When the user asks for persistence, ADD new tables to src/db/schema.ts using drizzle's sqliteTable helpers; don't rewrite the whole file unless asked.",
    "- bun:sqlite is server-only. Never import src/db/* from a React component that runs in the browser. If the user wants the UI to read DB data, you'll need a vite middleware /api route — for now just persist the schema definition and document the limitation in 'message'.",
    "- Available drizzle types in src/db/schema.ts: integer, text, real, blob, sqliteTable from drizzle-orm/sqlite-core.",
  ].join("\n");

  const contextBlock = Object.entries(ctxFiles)
    .filter(([, v]) => v !== null)
    .map(([p, v]) => `### ${p}\n\`\`\`\n${v}\n\`\`\``)
    .join("\n\n");

  const historyBlock = history.length === 0
    ? ""
    : `Recent turn summaries (most recent last):\n${history.map((h) => `- user: ${h.user}\n  agent: ${h.message ?? "(no message)"}`).join("\n")}\n`;

  const userMessage = `${historyBlock}\nCurrent workspace files:\n\n${contextBlock}\n\nUser request: ${prompt}`;

  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) {
    throw new Error("no LLM configured");
  }
  const resp = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "x-api-key": apiKey,
      "anthropic-version": "2023-06-01",
      "content-type": "application/json",
    },
    body: JSON.stringify({
      model: MODEL,
      max_tokens: 8192,
      stream: true,
      system,
      messages: [{ role: "user", content: userMessage }],
    }),
  });
  if (!resp.ok) {
    const text = await resp.text();
    throw new Error(`anthropic ${resp.status}: ${text.slice(0, 500)}`);
  }
  if (!resp.body) {
    throw new Error("anthropic: empty response body");
  }

  // Stream parser. Anthropic emits SSE messages separated by "\n\n".
  // Each message has `event:` + `data:` lines. We only care about
  // content_block_delta (text deltas) and message_delta (usage tally).
  const reader = resp.body.getReader();
  const decoder = new TextDecoder();
  let pending = "";
  let accumulated = "";
  let usage: { input_tokens: number; output_tokens: number } | undefined;

  // Throttle stream_chunk emits to ~every 80ms so the SSE feed isn't
  // flooded but the chat still feels live. Anthropic emits tokens at
  // ~50-100 tok/sec; this batches ~5-10 tokens per event.
  let chunkBuf = "";
  let lastFlush = Date.now();
  const FLUSH_INTERVAL_MS = 80;
  const flushChunk = (force = false) => {
    if (chunkBuf.length === 0) return;
    if (!force && Date.now() - lastFlush < FLUSH_INTERVAL_MS) return;
    emitStreamChunk(chunkBuf);
    chunkBuf = "";
    lastFlush = Date.now();
  };

  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    pending += decoder.decode(value, { stream: true });

    // Process every complete SSE message in the buffer.
    let nl;
    while ((nl = pending.indexOf("\n\n")) >= 0) {
      const raw = pending.slice(0, nl);
      pending = pending.slice(nl + 2);
      const data = sseDataLine(raw);
      if (!data) continue;
      try {
        const evt = JSON.parse(data) as {
          type: string;
          delta?: { type: string; text?: string };
          usage?: { input_tokens: number; output_tokens: number };
        };
        if (evt.type === "content_block_delta" && evt.delta?.type === "text_delta") {
          const text = evt.delta.text ?? "";
          accumulated += text;
          chunkBuf += text;
          flushChunk();
        } else if (evt.type === "message_delta" && evt.usage) {
          usage = evt.usage;
        }
      } catch {
        // ignore malformed event payloads
      }
    }
  }
  flushChunk(true);

  // Tolerate accidental markdown fences even though we told the model not to.
  const cleaned = accumulated
    .trim()
    .replace(/^```(?:json)?\s*/i, "")
    .replace(/```\s*$/i, "");
  let parsed: { thoughts: string; message: string; edits: Record<string, string> };
  try {
    parsed = JSON.parse(cleaned);
  } catch (e) {
    throw new Error(`LLM returned invalid JSON: ${(e as Error).message}; raw start: ${cleaned.slice(0, 200)}`);
  }
  return { ...parsed, usage };
}

/** Extract the `data: …` payload from a single SSE message. Returns
 *  empty string for keep-alive comments + heartbeats. */
function sseDataLine(message: string): string {
  let out = "";
  for (const line of message.split("\n")) {
    if (line.startsWith("data:")) {
      // Multi-line data is rare for Anthropic; concatenate just in case.
      out += line.slice(5).trim();
    }
  }
  return out;
}

async function main() {
  const prompt = process.argv.slice(2).join(" ").trim();
  if (!prompt) {
    emit({ role: "system", event_type: "message", content: "No prompt provided." });
    return;
  }

  // Echo a tiny "thought" so the UI shows immediate activity even
  // before the LLM round-trip completes.
  emit({ role: "assistant", event_type: "thought", content: "Reading workspace…" });

  const ctxFiles: Record<string, string | null> = {};
  for (const p of INCLUDE_PATHS) ctxFiles[p] = await readWorkspaceFile(p);
  const sources = await listSourceFiles();
  for (const p of sources) {
    if (!(p in ctxFiles)) ctxFiles[p] = await readWorkspaceFile(p);
  }
  const history = await loadHistoryTail();

  // No LLM configured → honest placeholder so the UX is observable
  // without an API key. Real edits arrive when ANTHROPIC_API_KEY is set.
  if (!process.env.ANTHROPIC_API_KEY) {
    emit({
      role: "assistant",
      event_type: "message",
      content:
        "I'm ready, but no LLM is wired on this deployment yet. Set ANTHROPIC_API_KEY on the proxifai pod to enable real edits. I see " +
        Object.keys(ctxFiles).filter((p) => ctxFiles[p] !== null).length +
        " files in the workspace.",
    });
    await appendHistory({ user: prompt, message: "(no LLM configured)" });
    return;
  }

  try {
    emit({ role: "assistant", event_type: "thought", content: "Asking the model…" });
    const result = await callLLM(prompt, ctxFiles, history);

    if (result.thoughts) {
      emit({ role: "assistant", event_type: "thought", content: result.thoughts });
    }
    const written = await applyEdits(result.edits ?? {});
    if (result.message) {
      const usage = result.usage
        ? {
            input_tokens: result.usage.input_tokens,
            output_tokens: result.usage.output_tokens,
            total_tokens: result.usage.input_tokens + result.usage.output_tokens,
          }
        : undefined;
      emit({ role: "assistant", event_type: "message", content: result.message, token_usage: usage });
    }
    await appendHistory({ user: prompt, thoughts: result.thoughts, message: result.message, files: written });
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    emit({ role: "system", event_type: "message", content: `Agent error: ${msg}` });
    await appendHistory({ user: prompt, message: `error: ${msg}` });
  }
}

await main();
