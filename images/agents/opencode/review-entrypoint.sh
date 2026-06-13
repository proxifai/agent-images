#!/bin/bash
# review-entrypoint.sh — opencode in PR-review mode.
#
# Invoked by entrypoint.sh when PROXIFAI_AGENT_MODE=review. Reads PR
# context from PROXIFAI_PR_* env vars (set by the trigger executor from
# the bridged forge.pr.opened event), produces a structured review with
# opencode, and POSTs it back via `pfai pr review --inline-file`.
#
# Unlike implement mode, we DO NOT clone-branch-commit-push. The agent's
# job here is to read the diff and emit feedback; no repo mutation.

set -euo pipefail

OUTPUT_LOG="/tmp/agent-output.log"
exec > >(tee -a "$OUTPUT_LOG") 2>&1

upload_output() {
    if [ -f "$OUTPUT_LOG" ] && [ -s "$OUTPUT_LOG" ]; then
        pfai exec output --file "$OUTPUT_LOG" 2>/dev/null || true
    fi
}
trap upload_output EXIT

# ─── Validate required PR context ───────────────────────────────────
require_env() {
    if [ -z "${!1:-}" ]; then
        echo "ERROR: $1 not set — review mode needs PR context from trigger executor"
        pfai exec status failed 2>/dev/null || true
        exit 2
    fi
}
require_env PROXIFAI_PR_NUMBER
require_env PROXIFAI_REPO_OWNER
require_env PROXIFAI_REPO_NAME
require_env PROXIFAI_PR_HEAD_SHA

PR_NUMBER="${PROXIFAI_PR_NUMBER}"
REPO_OWNER="${PROXIFAI_REPO_OWNER}"
REPO_NAME="${PROXIFAI_REPO_NAME}"
HEAD_SHA="${PROXIFAI_PR_HEAD_SHA}"
BASE_SHA="${PROXIFAI_PR_BASE_SHA:-}"
BASE_REF="${PROXIFAI_PR_BASE:-main}"
PR_TITLE="${PROXIFAI_PR_TITLE:-}"

echo "=== Review mode ==="
echo "Repo:   ${REPO_OWNER}/${REPO_NAME}"
echo "PR:     #${PR_NUMBER}"
echo "Head:   ${HEAD_SHA}"
echo "Base:   ${BASE_REF}${BASE_SHA:+ ($BASE_SHA)}"

# ─── Clone the repo (shallow, both base+head) ───────────────────────
CLONE_URL="${PROXIFAI_REPO_CLONE_URL:?missing PROXIFAI_REPO_CLONE_URL}"
if [ -n "${PROXIFAI_GIT_TOKEN:-}" ]; then
    CLONE_URL="$(echo "$CLONE_URL" | sed "s|://|://agent:${PROXIFAI_GIT_TOKEN}@|")"
fi
git config --global user.name "ProxifAI Review Bot"
git config --global user.email "review-bot@proxifai.com"
git config --global advice.detachedHead false

mkdir -p /workspace
cd /workspace
echo "Cloning ${PROXIFAI_REPO_CLONE_URL} ..."
if ! git clone --no-checkout "$CLONE_URL" repo 2>&1; then
    echo "ERROR: git clone failed"
    pfai exec status failed 2>/dev/null || true
    exit 3
fi
cd repo
git fetch origin "$HEAD_SHA" 2>&1 || true
git fetch origin "$BASE_REF" 2>&1 || true
git checkout "$HEAD_SHA" 2>&1

# Resolve the merge-base if BASE_SHA wasn't passed.
if [ -z "$BASE_SHA" ]; then
    BASE_SHA="$(git merge-base "origin/${BASE_REF}" HEAD 2>/dev/null || echo "origin/${BASE_REF}")"
fi
echo "Effective base: $BASE_SHA"

# ─── Generate the diff to review ────────────────────────────────────
DIFF_FILE=/tmp/review.diff
git diff --unified=3 "$BASE_SHA" "$HEAD_SHA" > "$DIFF_FILE"
DIFF_BYTES=$(wc -c < "$DIFF_FILE" | tr -d '[:space:]')
echo "Diff size: ${DIFF_BYTES} bytes"

if [ "$DIFF_BYTES" = "0" ]; then
    echo "Empty diff — nothing to review."
    pfai pr review "$PR_NUMBER" \
        --owner "$REPO_OWNER" --repo "$REPO_NAME" \
        --event comment --body "Proxifai code review bot: no diff to review."
    pfai exec status completed 2>/dev/null || true
    exit 0
fi

# Truncate enormous diffs so we don't blow context windows.
MAX_DIFF=200000
if [ "$DIFF_BYTES" -gt "$MAX_DIFF" ]; then
    echo "Truncating diff to ${MAX_DIFF} bytes for prompt fit"
    head -c "$MAX_DIFF" "$DIFF_FILE" > "$DIFF_FILE.truncated"
    mv "$DIFF_FILE.truncated" "$DIFF_FILE"
fi

# ─── Build the prompt ───────────────────────────────────────────────
# OpenCode runs as a coding agent; we steer it via a system-like preamble
# and require structured JSON output. The agent's free-form chatter goes
# into "summary"; per-line annotations go into "comments[]" matching the
# pfai pr review --inline-file shape (path/line/body/side).
cat > /tmp/review-prompt.txt << PROMPT_EOF
You are a senior staff engineer performing a code review on a pull request.

Repository: ${REPO_OWNER}/${REPO_NAME}
Pull request: #${PR_NUMBER}
Title: ${PR_TITLE}

Read the unified diff below carefully. Your job is to produce a strict
JSON object with TWO fields:

  "summary": a single paragraph (<= 80 words) overall verdict
  "comments": an array of inline annotations, EACH with:
      "path"  — the file path as it appears in the +++ header
      "line"  — the 1-based line number in the NEW file (use the +
                side of the hunk, i.e. RIGHT side)
      "body"  — the concrete suggestion or concern (1-3 sentences)

Rules:
  - Output ONLY the JSON object. No markdown fences, no prose around it.
  - Use double-quoted JSON strings. Escape special characters properly.
  - Skip cosmetic / nitpicky comments — only flag things a reviewer
    would genuinely want changed.
  - If there is nothing wrong, return {"summary": "LGTM", "comments": []}.

=== DIFF ===
$(cat "$DIFF_FILE")
PROMPT_EOF

# ─── Run opencode ───────────────────────────────────────────────────
# When no LLM provider is wired (OPENAI_API_KEY / ANTHROPIC_API_KEY env
# is unset), opencode bails out fast with a non-zero exit and no usable
# review text. Detect that up front and surface a clear fallback review
# so the PR still gets a status comment — better than the review
# silently failing and the user wondering why no comment showed up.
echo "=== Running OpenCode ==="
RAW_OUT=/tmp/review-raw.txt
if [ -z "${ANTHROPIC_API_KEY:-}" ] && [ -z "${OPENAI_API_KEY:-}" ]; then
    cat > "$RAW_OUT" << 'NOKEYS'
{"summary": "Proxifai review bot: no LLM provider is wired (set ANTHROPIC_API_KEY or OPENAI_API_KEY via the LLM gateway). Diff was fetched but no automated review was performed.", "comments": []}
NOKEYS
elif ! opencode -p "$(cat /tmp/review-prompt.txt)" -c /workspace/repo > "$RAW_OUT" 2>&1; then
    echo "WARNING: opencode exited non-zero — proceeding with whatever output we have"
fi
echo "OpenCode output: $(wc -c < "$RAW_OUT") bytes"

# ─── Extract the JSON object from the raw output ────────────────────
# OpenCode may wrap output in markdown fences despite the prompt. Strip
# fences and isolate the first {...} block, then normalize. Uses jq
# (already present in the base image) instead of python3 to keep the
# review path agnostic of the agent image's interpreter choice.
JSON_FILE=/tmp/review.json
sed -nE 's/^.*```(json)?[[:space:]]*$//; p' "$RAW_OUT" | \
    awk '/^\{/{found=1} found{print}' > /tmp/review-stripped.json

# If the stripped output is empty or invalid, fall through to a safe stub.
if ! jq empty </tmp/review-stripped.json >/dev/null 2>&1; then
    echo "WARNING: opencode output was not parseable JSON — using stub"
    echo '{"summary":"Proxifai bot: opencode output was not valid JSON.","comments":[]}' > "$JSON_FILE"
else
    # Normalize the schema: coerce types, drop malformed entries, default side=RIGHT.
    jq '{
        summary: (.summary // "" | tostring),
        comments: [(.comments // [])[] |
            select(type == "object") |
            select((.path // "") != "" and (.body // "") != "" and ((.line // 0) | tonumber) > 0) |
            {
                path: (.path | tostring),
                line: (.line | tonumber),
                side: (.side // "RIGHT" | ascii_upcase),
                body: (.body | tostring)
            }
        ]
    }' /tmp/review-stripped.json > "$JSON_FILE"
fi

SUMMARY="$(jq -r '.summary // empty' "$JSON_FILE")"
COMMENT_COUNT="$(jq '.comments | length' "$JSON_FILE" 2>/dev/null || echo 0)"
# Default both fields so downstream tests / pfai-cli never see empty
# strings — empty summary on an event=COMMENT review is a 400.
if [ -z "$SUMMARY" ]; then
    SUMMARY="Proxifai bot: opencode finished without a summary."
fi
if ! [ "$COMMENT_COUNT" -ge 0 ] 2>/dev/null; then
    COMMENT_COUNT=0
fi
echo "Review summary: $SUMMARY"
echo "Inline comments: $COMMENT_COUNT"

# Write the comments array to a separate file the CLI can ingest.
jq '.comments' "$JSON_FILE" > /tmp/review-comments.json

# ─── Decide review event ────────────────────────────────────────────
# Default to "comment". Could elevate to "request_changes" when the agent
# flags ≥1 issue; we keep it conservative since false positives are
# annoying. Operators who want stricter behavior can override via
# PROXIFAI_REVIEW_EVENT.
REVIEW_EVENT="${PROXIFAI_REVIEW_EVENT:-comment}"
if [ "$REVIEW_EVENT" = "auto" ]; then
    if [ "$COMMENT_COUNT" -gt 0 ]; then
        REVIEW_EVENT="request_changes"
    else
        REVIEW_EVENT="comment"
    fi
fi

# ─── Post the review ────────────────────────────────────────────────
echo "Posting review (event=${REVIEW_EVENT}) ..."
PR_REVIEW_CMD=(pfai pr review "$PR_NUMBER"
    --owner "$REPO_OWNER" --repo "$REPO_NAME"
    --event "$REVIEW_EVENT"
    --body "$SUMMARY"
)
if [ "$COMMENT_COUNT" -gt 0 ]; then
    PR_REVIEW_CMD+=(--inline-file /tmp/review-comments.json)
fi
if "${PR_REVIEW_CMD[@]}"; then
    echo "=== Review submitted ==="
    pfai exec status completed 2>/dev/null || true
    exit 0
else
    echo "ERROR: pfai pr review failed"
    pfai exec status failed 2>/dev/null || true
    exit 4
fi
