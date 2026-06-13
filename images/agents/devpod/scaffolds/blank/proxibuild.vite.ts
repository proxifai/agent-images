/* ProxiBuild Vite/Babel plumbing — Visual Edit support.
 *
 *   proxibuildBabelPlugin     adds data-pb-id="relpath:line:col" to every
 *                             host JSX element at compile time. The ID is
 *                             stable across re-renders inside a single
 *                             agent turn and identifies elements for the
 *                             iframe overlay's click handler.
 *
 *   proxibuildOverlayPlugin   serves /__proxibuild/overlay.js and injects
 *                             a <script> tag into index.html in dev mode.
 *                             The overlay listens for clicks on tagged
 *                             elements and postMessages selection details
 *                             to the parent window (the proxifai builder).
 *
 * Together they let a user click an element in the live preview iframe
 * and inline-edit its text — that text edit lands in the source file via
 * proxifai's /api/v1/.../visual-edits endpoint, vite HMR fires, the
 * iframe re-renders. Same UX as Lovable's Visual Edits.
 */
import type { PluginObj, PluginPass } from "@babel/core";
import type { Plugin as VitePlugin } from "vite";

interface BabelPluginOptions {
  /** Workspace root to strip from absolute filenames so the data-pb-id
   *  is portable across pod restarts. Default: process.cwd(). */
  workspace?: string;
}

export function proxibuildBabelPlugin(
  babel: { types: typeof import("@babel/types") },
): PluginObj<PluginPass & { opts: BabelPluginOptions }> {
  const t = babel.types;
  return {
    name: "proxibuild-element-tag",
    visitor: {
      JSXOpeningElement(path, state) {
        const node = path.node;
        // Host elements only — we want to tag <h1>, <div>, etc., not
        // React components (uppercase). Tagging components would
        // attach data-pb-id to the WRAPPER component and lose us the
        // ability to target the actual host element the user clicked.
        if (!t.isJSXIdentifier(node.name)) return;
        if (!/^[a-z]/.test(node.name.name)) return;
        // Already tagged (idempotent re-runs).
        for (const attr of node.attributes) {
          if (
            t.isJSXAttribute(attr) &&
            t.isJSXIdentifier(attr.name) &&
            attr.name.name === "data-pb-id"
          ) {
            return;
          }
        }
        const loc = node.loc;
        if (!loc) return;
        const filename = state.filename || "unknown.tsx";
        const workspace = (state.opts && state.opts.workspace) || process.cwd();
        const rel = filename.startsWith(workspace)
          ? filename.slice(workspace.length).replace(/^\//, "")
          : filename;
        const id = `${rel}:${loc.start.line}:${loc.start.column}`;
        node.attributes.push(
          t.jsxAttribute(t.jsxIdentifier("data-pb-id"), t.stringLiteral(id)),
        );
      },
    },
  };
}

// The overlay script. Plain JS so we don't need a build step. It runs
// in the iframe's window, listens for parent.postMessage to toggle
// edit mode, and emits selection events on click.
//
// Outline color is var(--pb-outline) so the iframe app can override it
// if it ever needs to (e.g. dark vs. light). Default is indigo.
const OVERLAY_SCRIPT = String.raw`(() => {
  if (window.__proxibuildOverlayLoaded) return;
  window.__proxibuildOverlayLoaded = true;

  let editMode = false;
  let hoverEl = null;
  let selectedEl = null;

  const HOVER_OUTLINE = "2px solid var(--pb-hover-outline, #6366f1)";
  const SELECT_OUTLINE = "2px solid var(--pb-select-outline, #f59e0b)";

  function findTaggedAncestor(el) {
    while (el && el !== document.body && el.nodeType === 1) {
      if (el.getAttribute && el.getAttribute("data-pb-id")) return el;
      el = el.parentElement;
    }
    return null;
  }

  function clearHover() {
    if (hoverEl && hoverEl !== selectedEl) {
      hoverEl.style.outline = "";
      hoverEl.style.outlineOffset = "";
    }
    hoverEl = null;
  }

  function clearSelected() {
    if (selectedEl) {
      selectedEl.style.outline = "";
      selectedEl.style.outlineOffset = "";
    }
    selectedEl = null;
  }

  function setSelected(el) {
    clearSelected();
    if (!el) return;
    el.style.outline = SELECT_OUTLINE;
    el.style.outlineOffset = "1px";
    selectedEl = el;
  }

  document.addEventListener("mouseover", (e) => {
    if (!editMode) return;
    const target = findTaggedAncestor(e.target);
    if (target === hoverEl) return;
    clearHover();
    if (target && target !== selectedEl) {
      target.style.outline = HOVER_OUTLINE;
      target.style.outlineOffset = "1px";
      hoverEl = target;
    }
  }, true);

  document.addEventListener("mouseout", () => {
    if (!editMode) return;
    clearHover();
  }, true);

  document.addEventListener("click", (e) => {
    if (!editMode) return;
    const target = findTaggedAncestor(e.target);
    if (!target) return;
    e.preventDefault();
    e.stopPropagation();
    setSelected(target);
    const rect = target.getBoundingClientRect();
    parent.postMessage({
      type: "proxibuild.select",
      id: target.getAttribute("data-pb-id"),
      tag: target.tagName.toLowerCase(),
      text: target.textContent || "",
      rect: { x: rect.x, y: rect.y, width: rect.width, height: rect.height }
    }, "*");
  }, true);

  // Block bubble-up click side effects (router navigations etc.) while
  // edit mode is on. Without this, clicking a <Link> takes the iframe
  // to a different route.
  document.addEventListener("auxclick", (e) => {
    if (editMode) { e.preventDefault(); e.stopPropagation(); }
  }, true);
  document.addEventListener("submit", (e) => {
    if (editMode) { e.preventDefault(); e.stopPropagation(); }
  }, true);

  window.addEventListener("message", (e) => {
    if (!e.data || typeof e.data !== "object") return;
    if (e.data.type === "proxibuild.set-mode") {
      editMode = !!e.data.enabled;
      if (!editMode) { clearHover(); clearSelected(); }
      document.documentElement.classList.toggle("proxibuild-edit-mode", editMode);
    } else if (e.data.type === "proxibuild.clear-selection") {
      clearSelected();
    }
  });

  // ─── Runtime + build error capture ───────────────────────────────
  // Posts a {type:"proxibuild.iframe-error", message, stack, source}
  // to the parent on any uncaught error or unhandled promise rejection.
  // The parent (proxibuild's preview-pane) forwards these to the build
  // service as system-role transcript entries so the user sees the
  // error in chat — and the agent can read them on the next turn.
  const seenErrors = new Set();
  function reportError(payload) {
    // Dedupe rapid repeats of the same error in a short window. Vite
    // HMR sometimes re-throws the same module-eval error 3-4 times in
    // a single failed reload.
    const sig = (payload.message || "") + "|" + (payload.source || "");
    if (seenErrors.has(sig)) return;
    seenErrors.add(sig);
    setTimeout(() => seenErrors.delete(sig), 3000);
    parent.postMessage({ type: "proxibuild.iframe-error", ...payload }, "*");
  }
  window.addEventListener("error", (e) => {
    reportError({
      message: e.message || String(e.error || ""),
      stack: e.error && e.error.stack ? String(e.error.stack) : undefined,
      source: e.filename || undefined,
      line: e.lineno,
      col: e.colno,
      kind: "error",
    });
  });
  window.addEventListener("unhandledrejection", (e) => {
    const reason = e.reason;
    const msg = reason && reason.message ? reason.message : String(reason);
    reportError({
      message: msg,
      stack: reason && reason.stack ? String(reason.stack) : undefined,
      kind: "unhandledrejection",
    });
  });

  // Announce ready so the parent can post the initial mode.
  parent.postMessage({ type: "proxibuild.overlay-ready" }, "*");
})();
`;

export function proxibuildOverlayPlugin(): VitePlugin {
  return {
    name: "proxibuild-overlay",
    apply: "serve", // dev-server only; production builds skip the overlay.
    configureServer(server) {
      server.middlewares.use("/__proxibuild/overlay.js", (_req, res) => {
        res.setHeader("Content-Type", "application/javascript; charset=utf-8");
        res.setHeader("Cache-Control", "no-store");
        res.end(OVERLAY_SCRIPT);
      });
    },
    transformIndexHtml(html) {
      // Inject before </body> so the script runs after the React mount
      // point exists. Module type so it's deferred + has top-level await
      // semantics if we ever need them.
      return html.replace(
        "</body>",
        `  <script type="module" src="/__proxibuild/overlay.js"></script>\n  </body>`,
      );
    },
  };
}
