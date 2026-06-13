#!/usr/bin/env bun
/**
 * visual-edit.ts — applies a Visual Edit text change to a source file.
 *
 * Invoked by proxifai's build.Service.ApplyVisualEdit via kubectl exec:
 *   bun visual-edit.ts --id "src/App.tsx:42:5" --kind text --value "new heading"
 *
 * The id format is `<relative-path>:<1-indexed-line>:<0-indexed-column>`
 * — same format the proxibuild babel plugin writes to data-pb-id at
 * compile time. We open the file at /workspace/<path>, find the JSX
 * opening tag starting at that line:col, locate its matching closing
 * tag, swap the text content with `value`, write the file back.
 *
 * Constraints (v1):
 *   - Text-only edits (kind=text).
 *   - Only works for elements whose children are plain text — refuses
 *     when nested JSX is detected. Most leaf elements (<h1>, <p>, <span>,
 *     <button>, <a>) qualify.
 *   - Element may span up to 6 lines from opening to closing tag.
 *
 * Emits one NDJSON line on stdout: { ok, file, tag, oldText, newText }
 * on success, or { ok:false, error } on failure. Same convention as the
 * other in-pod helpers (agent.ts, db-introspect.ts) so the Go side parses
 * uniformly.
 */
import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

function emit(obj: Record<string, unknown>): never {
  process.stdout.write(JSON.stringify(obj) + "\n");
  process.exit(obj.ok ? 0 : 1);
}

const args = parseArgs(process.argv.slice(2));
if (!args.id) emit({ ok: false, error: "--id required" });
if (args.kind && args.kind !== "text") emit({ ok: false, error: "only kind=text supported in v1" });
const newText = args.value ?? "";

const idMatch = args.id!.match(/^(.+):(\d+):(\d+)$/);
if (!idMatch) emit({ ok: false, error: `invalid id format: ${args.id}` });
const [, relPath, lineStr, colStr] = idMatch!;
const lineNum = parseInt(lineStr, 10); // 1-indexed
const colNum = parseInt(colStr, 10); // 0-indexed

const workspace = process.env.WORKSPACE ?? "/workspace";
const absPath = join(workspace, relPath);

let content: string;
try {
  content = readFileSync(absPath, "utf8");
} catch (e) {
  emit({ ok: false, error: `read ${relPath}: ${(e as Error).message}` });
}

const lines = content!.split("\n");
if (lineNum < 1 || lineNum > lines.length) {
  emit({ ok: false, error: `line ${lineNum} out of range (file has ${lines.length})` });
}
const startLine = lines[lineNum - 1];
if (colNum < 0 || colNum > startLine.length) {
  emit({ ok: false, error: `col ${colNum} out of range on line ${lineNum} (len ${startLine.length})` });
}
const sliceFromCol = startLine.slice(colNum);
const tagMatch = sliceFromCol.match(/^<([A-Za-z][A-Za-z0-9_:-]*)/);
if (!tagMatch) {
  emit({ ok: false, error: `no JSX opening tag at ${relPath}:${lineNum}:${colNum}` });
}
const tagName = tagMatch![1];

// Find the end of the opening tag — first `>` not inside quotes.
const openTagEnd = findUnquotedGt(sliceFromCol);
if (openTagEnd === -1) {
  emit({ ok: false, error: `couldn't find end of opening tag for <${tagName}>` });
}
if (sliceFromCol[openTagEnd - 1] === "/") {
  emit({ ok: false, error: `<${tagName}> is self-closing — no text content to edit` });
}

// Walk forward from after the opening `>` until we hit </tagname>.
// Allow up to 6 lines so multi-line elements still work.
const closingRe = new RegExp(`</\\s*${tagName}\\s*>`);
let combined = sliceFromCol.slice(openTagEnd + 1);
let extraLines = 0;
while (!closingRe.test(combined)) {
  const nextIdx = lineNum - 1 + extraLines + 1;
  if (extraLines >= 6 || nextIdx >= lines.length) {
    emit({ ok: false, error: `couldn't find </${tagName}> within 6 lines` });
  }
  combined += "\n" + lines[nextIdx];
  extraLines++;
}
const closingMatch = combined.match(closingRe)!;
const childText = combined.slice(0, closingMatch.index);

// Conservative nested-JSX guard. < followed by letter or / inside child
// text indicates a nested element. Single < that's part of a comparison
// expression like {a < b} would also trip this — accept the false
// positive in v1.
if (/<[A-Za-z\/]/.test(childText)) {
  emit({ ok: false, error: `<${tagName}> contains nested JSX — text-only edits unsupported in v1` });
}

// Build the new file. Splice the rebuilt span (opening tag + new text +
// closing tag) back into the source.
const escapedNewText = escapeJSXText(newText);
const newCombined = escapedNewText + combined.slice(closingMatch.index!);
const newCombinedLines = newCombined.split("\n");
const newStartLine =
  startLine.slice(0, colNum) +
  sliceFromCol.slice(0, openTagEnd + 1) +
  newCombinedLines[0];
const out = [
  ...lines.slice(0, lineNum - 1),
  newStartLine,
  ...newCombinedLines.slice(1),
  ...lines.slice(lineNum + extraLines),
];

try {
  writeFileSync(absPath, out.join("\n"), "utf8");
} catch (e) {
  emit({ ok: false, error: `write ${relPath}: ${(e as Error).message}` });
}

emit({
  ok: true,
  file: relPath,
  tag: tagName,
  oldText: childText.trim(),
  newText,
});

// ---------- helpers ----------

function parseArgs(argv: string[]): Record<string, string> {
  const out: Record<string, string> = {};
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a.startsWith("--") && i + 1 < argv.length) {
      out[a.slice(2)] = argv[++i];
    }
  }
  return out;
}

/** Find the first '>' that isn't inside a single/double/backtick-quoted
 *  string. Returns -1 if none. */
function findUnquotedGt(s: string): number {
  let i = 0;
  while (i < s.length) {
    const c = s[i];
    if (c === ">") return i;
    if (c === '"' || c === "'" || c === "`") {
      const quote = c;
      i++;
      while (i < s.length && s[i] !== quote) {
        if (s[i] === "\\") i++;
        i++;
      }
    }
    i++;
  }
  return -1;
}

/** Minimal JSX text escape: `{` and `}` must be braced when they appear
 *  in a text node, since they'd otherwise be parsed as expression
 *  delimiters. Plain `<` would also break — but the validation above
 *  refuses payloads containing `<`. */
function escapeJSXText(s: string): string {
  return s.replace(/[{}]/g, (m) => `{'${m}'}`);
}
