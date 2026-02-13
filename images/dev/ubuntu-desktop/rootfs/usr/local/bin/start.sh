#!/bin/bash
set -e

DISPLAY="${DISPLAY:-:99}"
RESOLUTION="${RESOLUTION:-1920x1080x24}"
VNC_PORT="${VNC_PORT:-5900}"
USER_NAME="user"
USER_HOME="/home/${USER_NAME}"

echo "[ubuntu-desktop] Starting Xvfb on ${DISPLAY} at ${RESOLUTION}..."
Xvfb "${DISPLAY}" -screen 0 "${RESOLUTION}" -ac +extension GLX +render -noreset &

# Wait for display to be ready
for i in $(seq 1 30); do
    if xdpyinfo -display "${DISPLAY}" >/dev/null 2>&1; then
        echo "[ubuntu-desktop] Display ${DISPLAY} ready"
        break
    fi
    if [ "$i" -eq 30 ]; then
        echo "[ubuntu-desktop] ERROR: Display ${DISPLAY} failed to start"
        exit 1
    fi
    sleep 0.2
done

# Allow the user to access the X display
xhost +local: >/dev/null 2>&1 || true

# Start desktop session as non-root user
# This ensures browsers and GUI apps work without --no-sandbox
runuser -u "${USER_NAME}" -- bash -c "
    export DISPLAY=${DISPLAY}
    export HOME=${USER_HOME}
    export XDG_RUNTIME_DIR=/tmp/runtime-${USER_NAME}
    mkdir -p \${XDG_RUNTIME_DIR}

    # Start dbus session (required for XFCE)
    eval \$(dbus-launch --sh-syntax)
    export DBUS_SESSION_BUS_ADDRESS

    echo '[ubuntu-desktop] Starting XFCE4 desktop...'
    startxfce4 &

    sleep 2

    echo '[ubuntu-desktop] Starting x11vnc on port ${VNC_PORT}...'
    x11vnc -display ${DISPLAY} -forever -shared -rfbport ${VNC_PORT} -nopw -noxdamage -xkb &

    # Open a terminal on startup
    xfce4-terminal --geometry=120x35 --working-directory=/workspace &

    echo '[ubuntu-desktop] Desktop ready - VNC on port ${VNC_PORT}'

    # Keep this subshell alive
    wait
" &

# Run sshd as PID 1 for container lifecycle
exec /usr/sbin/sshd -D -e
