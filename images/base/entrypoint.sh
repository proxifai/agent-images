#!/bin/bash
set -euo pipefail

# ─── ProxifAI Generic Agent Entrypoint ───
# Handles the full agent lifecycle for all tool types.
# Tool-specific command is selected via PROXIFAI_AGENT_TOOL env var.
# The agent workflow runs inside a tmux session so terminal UI users
# can see live output when they connect via SSH.

OUTPUT_LOG="/tmp/agent-output.log"

upload_output() {
    if [ -f "$OUTPUT_LOG" ] && [ -s "$OUTPUT_LOG" ]; then
        pfai exec output --file "$OUTPUT_LOG" 2>/dev/null || true
    fi
}

# Log helper for the setup phase (before tmux takes over)
log() { echo "$@" | tee -a "$OUTPUT_LOG"; }

# ─── ERR trap: report failure on unhandled errors during setup ───
report_failure() {
    local exit_code=$?
    local line_no=$1
    log "ERROR: entrypoint failed at line $line_no (exit code $exit_code)"
    upload_output
    pfai exec status failed --error "Entrypoint crashed at line $line_no (exit $exit_code)" 2>/dev/null || true
}
trap 'report_failure $LINENO' ERR

# ─── Start sshd in background so users can always SSH in ───
/usr/sbin/sshd -e 2>/dev/null || true

# ─── Set up tmux auto-attach for SSH terminal sessions ───
# When users open the terminal UI, their SSH session auto-attaches
# to the running agent tmux session to see live output.
cat > /etc/profile.d/tmux-attach.sh << 'PROFILE_EOF'
if [ -n "$SSH_CONNECTION" ] && [ -z "$TMUX" ] && tmux has-session -t agent 2>/dev/null; then
    exec tmux attach-session -t agent
fi
PROFILE_EOF

# ─── Configure tmux for clean terminal experience ───
cat > /root/.tmux.conf << 'TMUX_CONF'
set -g status off
set -g mouse on
set -g history-limit 50000
TMUX_CONF

log "=== ProxifAI Agent ==="
log "Tool: ${PROXIFAI_AGENT_TOOL:-unknown}"
log "Execution ID: ${PROXIFAI_EXECUTION_ID:-unknown}"
log "Task: ${PROXIFAI_TASK_TITLE:-none}"

# ─── If no repo clone URL, fall back to interactive mode ───
if [ -z "${PROXIFAI_REPO_CLONE_URL:-}" ]; then
    log "No PROXIFAI_REPO_CLONE_URL set — running in interactive mode."
    upload_output
    tmux new-session -d -s agent "cd /workspace && exec bash"
    exec sleep infinity
fi

# ─── Set up git credentials ───
CLONE_URL="${PROXIFAI_REPO_CLONE_URL}"

if [ -n "${PROXIFAI_GIT_TOKEN:-}" ]; then
    CLONE_URL=$(echo "$CLONE_URL" | sed "s|://|://agent:${PROXIFAI_GIT_TOKEN}@|")
fi

AGENT_SLUG=$(echo "${PROXIFAI_AGENT_NAME:-agent}" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9-')
git config --global user.name "${PROXIFAI_AGENT_NAME:-ProxifAI Agent}"
git config --global user.email "${AGENT_SLUG}[bot]@proxifai.com"

# ─── Clone the repo ───
log "Cloning ${PROXIFAI_REPO_CLONE_URL} ..."
if ! git clone "$CLONE_URL" /workspace/repo 2>&1 | tee -a "$OUTPUT_LOG"; then
    log "ERROR: git clone failed"
    pfai exec status failed --error "git clone failed" 2>/dev/null || true
    upload_output
    exec sleep infinity
fi

cd /workspace/repo
git checkout -b "${PROXIFAI_BRANCH_NAME:-agent/task}"

# ─── Save prompt to file (avoids quoting issues with tmux) ───
cat > /tmp/agent-prompt.txt << PROMPT_EOF
You are an AI agent working on a software task.

Task: ${PROXIFAI_TASK_TITLE}
${PROXIFAI_TASK_DESCRIPTION:+
Description: ${PROXIFAI_TASK_DESCRIPTION}}

Instructions:
- Analyze the codebase and implement the required changes
- Make clean, focused commits
- Do not ask questions — make reasonable decisions and proceed
PROMPT_EOF

# ─── Write agent workflow script (runs inside tmux for terminal visibility) ───
cat > /tmp/agent-workflow.sh << 'WORKFLOW_EOF'
#!/bin/bash
set -uo pipefail

# Capture all output to log file AND to the tmux terminal
exec > >(tee -a /tmp/agent-output.log) 2>&1

# On any error, drop into a shell so the tmux session stays alive
trap 'echo ""; echo "=== Workflow error — dropping to shell ==="; exec bash' ERR

cd /workspace/repo

BRANCH="$(git branch --show-current)"
DEFAULT_BRANCH="${PROXIFAI_REPO_DEFAULT_BRANCH:-main}"
PROMPT="$(cat /tmp/agent-prompt.txt)"
TOOL="${PROXIFAI_AGENT_TOOL:-opencode}"
TOOL_EXIT=0

echo "=== Running $TOOL ==="
echo "Branch: $BRANCH"
echo ""

# ─── Run the tool-specific command ───
case "$TOOL" in
    opencode)
        opencode -p "$PROMPT" -c /workspace/repo 2>&1 || TOOL_EXIT=$?
        ;;
    claude-code)
        claude --print "$PROMPT" \
            --allowedTools "Edit,Write,Bash,Read,Glob,Grep" \
            --output-format stream-json \
            2>&1 || TOOL_EXIT=$?
        ;;
    aider)
        aider --message "$PROMPT" --yes --no-input 2>&1 || TOOL_EXIT=$?
        ;;
    gemini-cli)
        gemini "$PROMPT" 2>&1 || TOOL_EXIT=$?
        ;;
    copilot|cursor)
        echo "$TOOL does not support non-interactive mode. Container will stay alive for SSH."
        pfai exec status failed --error "$TOOL: no non-interactive mode available" 2>/dev/null || true
        exec bash
        ;;
    *)
        echo "WARNING: Unknown tool '$TOOL', skipping automated execution."
        pfai exec status failed --error "unknown agent tool: $TOOL" 2>/dev/null || true
        exec bash
        ;;
esac

if [ "$TOOL_EXIT" -ne 0 ]; then
    echo "WARNING: $TOOL exited with status $TOOL_EXIT"
fi

# ─── Check for changes ───
if git diff --quiet HEAD && git diff --cached --quiet && [ -z "$(git ls-files --others --exclude-standard)" ]; then
    echo "No changes were made by the agent."
    if [ "$TOOL_EXIT" -ne 0 ]; then
        pfai exec status failed --error "$TOOL exited with status $TOOL_EXIT and made no changes" 2>/dev/null || true
    else
        pfai exec status completed 2>/dev/null || true
    fi
    echo ""
    echo "=== Agent work complete (no changes) ==="
    exec bash
fi

# ─── Stage and commit ───
git add -A
if ! git diff --cached --quiet; then
    git commit -m "feat: ${PROXIFAI_TASK_TITLE}

Automated changes by ProxifAI Agent ($TOOL)
Task: #${PROXIFAI_TASK_NUMBER:-0}" 2>&1
fi

# ─── Push ───
echo "Pushing branch $BRANCH ..."
if ! git push origin "$BRANCH" 2>&1; then
    echo "ERROR: git push failed"
    pfai exec status failed --error "git push failed" 2>/dev/null || true
    echo ""
    echo "=== Agent work failed (push error) ==="
    exec bash
fi
echo "=== Push successful ==="

# ─── Create Pull Request ───
echo "Creating pull request ..."
PR_BODY="Automated PR by ProxifAI Agent ($TOOL)

**Task:** #${PROXIFAI_TASK_NUMBER:-0} — ${PROXIFAI_TASK_TITLE}
${PROXIFAI_TASK_DESCRIPTION:+
**Description:** ${PROXIFAI_TASK_DESCRIPTION}}"

PR_NUM=""
PR_OUTPUT=$(pfai pr create \
    --owner "${PROXIFAI_REPO_OWNER}" \
    --repo "${PROXIFAI_REPO_NAME}" \
    --title "${PROXIFAI_TASK_TITLE}" \
    --head "$BRANCH" \
    --base "$DEFAULT_BRANCH" \
    --body "$PR_BODY" \
    --json 2>&1) && {
    PR_NUM=$(echo "$PR_OUTPUT" | jq -r '.number // empty' 2>/dev/null)
    echo "=== Pull request created (PR #${PR_NUM}) ==="
} || echo "WARNING: PR creation failed (changes still pushed to branch $BRANCH)"

# ─── Report completion ───
if [ -n "$PR_NUM" ]; then
    pfai exec status completed --pr "$PR_NUM" 2>/dev/null || true
else
    pfai exec status completed 2>/dev/null || true
fi

echo ""
echo "=== Agent work complete ==="
echo "Container staying alive for inspection."

# Upload output
if [ -f "/tmp/agent-output.log" ] && [ -s "/tmp/agent-output.log" ]; then
    pfai exec output --file "/tmp/agent-output.log" 2>/dev/null || true
fi

# Drop into shell for post-run inspection
exec bash
WORKFLOW_EOF
chmod +x /tmp/agent-workflow.sh

# ─── Disable ERR trap (workflow script handles its own errors) ───
trap - ERR

# ─── Start the agent workflow inside a tmux session ───
log "Starting agent workflow in tmux session..."
tmux new-session -d -s agent /tmp/agent-workflow.sh

# ─── Wait for tmux session and periodically upload output ───
while tmux has-session -t agent 2>/dev/null; do
    sleep 10
    upload_output
done

# Final upload and keep container alive
upload_output
exec sleep infinity
