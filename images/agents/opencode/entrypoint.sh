#!/bin/bash
set -euo pipefail

OUTPUT_LOG="/tmp/agent-output.log"

upload_output() {
    if [ -f "$OUTPUT_LOG" ] && [ -s "$OUTPUT_LOG" ]; then
        pfai exec output --file "$OUTPUT_LOG" 2>/dev/null || true
    fi
}

# ─── Start sshd in background so users can SSH in ───
/usr/sbin/sshd -e

# ─── Auto-attach SSH sessions to the agent tmux session ───
# When users open the terminal UI, their SSH session auto-attaches to see live output
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

echo "=== ProxifAI OpenCode Agent ==="
echo "Execution ID: ${PROXIFAI_EXECUTION_ID:-unknown}"
echo "Task: ${PROXIFAI_TASK_TITLE:-none}"

# ─── If no repo clone URL, just keep the container alive for interactive use ───
if [ -z "${PROXIFAI_REPO_CLONE_URL:-}" ]; then
    echo "No PROXIFAI_REPO_CLONE_URL set — running in interactive mode."
    upload_output
    tmux new-session -d -s agent "cd /workspace && exec bash"
    exec sleep infinity
fi

# ─── Set up git credentials ───
CLONE_URL="${PROXIFAI_REPO_CLONE_URL}"
if [ -n "${PROXIFAI_GIT_TOKEN:-}" ]; then
    CLONE_URL=$(echo "$CLONE_URL" | sed "s|://|://agent:${PROXIFAI_GIT_TOKEN}@|")
fi
git config --global user.name "ProxifAI Agent"
git config --global user.email "agent@proxifai.com"

# ─── Clone the repo ───
echo "Cloning ${PROXIFAI_REPO_CLONE_URL} ..."
if ! git clone "$CLONE_URL" /workspace/repo 2>&1; then
    echo "ERROR: git clone failed"
    pfai exec status failed 2>/dev/null || true
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
set -euo pipefail
exec > >(tee -a /tmp/agent-output.log) 2>&1

cd /workspace/repo

BRANCH="$(git branch --show-current)"
DEFAULT_BRANCH="${PROXIFAI_REPO_DEFAULT_BRANCH:-main}"
PROMPT="$(cat /tmp/agent-prompt.txt)"

echo "=== Running OpenCode ==="
echo "Branch: $BRANCH"
echo "Task: ${PROXIFAI_TASK_TITLE}"
echo ""

# ─── Run OpenCode in non-interactive mode ───
opencode -p "$PROMPT" -c /workspace/repo 2>&1
OPENCODE_EXIT=$?

if [ $OPENCODE_EXIT -eq 0 ]; then
    echo "=== OpenCode completed ==="
else
    echo "WARNING: OpenCode exited with non-zero status ($OPENCODE_EXIT)"
fi

# ─── Check if there are any changes (staged, unstaged, or untracked) ───
if git diff --quiet HEAD && git diff --cached --quiet && [ -z "$(git ls-files --others --exclude-standard)" ]; then
    echo "No changes were made by the agent."
    pfai exec status completed 2>/dev/null || true
    echo ""
    echo "=== Agent work complete (no changes) ==="
    exec bash
fi

# ─── Stage and commit ───
git add -A
if ! git diff --cached --quiet; then
    git commit -m "feat: ${PROXIFAI_TASK_TITLE}

Automated changes by ProxifAI Agent (OpenCode)
Task: #${PROXIFAI_TASK_NUMBER:-0}" 2>&1
fi

# ─── Push changes ───
echo "Pushing branch $BRANCH ..."
if ! git push origin "$BRANCH" 2>&1; then
    echo "ERROR: git push failed"
    pfai exec status failed 2>/dev/null || true
    echo ""
    echo "=== Agent work failed (push error) ==="
    exec bash
fi

echo "=== Push successful ==="

# ─── Create Pull Request via pfai CLI ───
echo "Creating pull request ..."
PR_BODY="Automated PR by ProxifAI Agent (OpenCode)

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
} || echo "WARNING: PR creation failed (changes are still pushed to branch $BRANCH)"

# ─── Update execution status (with PR number if available) ───
if [ -n "$PR_NUM" ]; then
    pfai exec status completed --pr "$PR_NUM" 2>/dev/null || true
else
    pfai exec status completed 2>/dev/null || true
fi

echo ""
echo "=== Agent work complete ==="
echo "Container staying alive for inspection."

# Upload terminal output
if [ -f "/tmp/agent-output.log" ] && [ -s "/tmp/agent-output.log" ]; then
    pfai exec output --file "/tmp/agent-output.log" 2>/dev/null || true
fi

# Drop into a shell for post-run inspection
exec bash
WORKFLOW_EOF
chmod +x /tmp/agent-workflow.sh

# ─── Start the agent workflow inside a tmux session ───
# Terminal UI users auto-attach to this session via /etc/profile.d/tmux-attach.sh
echo "Starting agent workflow in tmux session..."
tmux new-session -d -s agent /tmp/agent-workflow.sh

# ─── Wait for tmux session and periodically upload output ───
while tmux has-session -t agent 2>/dev/null; do
    sleep 10
    upload_output
done

# Final upload and keep container alive
upload_output
exec sleep infinity
