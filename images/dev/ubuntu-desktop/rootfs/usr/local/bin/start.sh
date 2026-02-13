#!/bin/bash
set -e

DISPLAY="${DISPLAY:-:99}"
RESOLUTION="${RESOLUTION:-1920x1080x24}"
VNC_PORT="${VNC_PORT:-5900}"

echo "[ubuntu-desktop] Starting Xvfb on ${DISPLAY} at ${RESOLUTION}..."
Xvfb "${DISPLAY}" -screen 0 "${RESOLUTION}" -ac +extension GLX +render -noreset &
XVFB_PID=$!

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

# Start dbus session (required for XFCE)
export $(dbus-launch)
echo "[ubuntu-desktop] D-Bus session started"

echo "[ubuntu-desktop] Starting XFCE4 desktop..."
startxfce4 &

# Wait a moment for XFCE to initialize
sleep 2

echo "[ubuntu-desktop] Starting x11vnc on port ${VNC_PORT}..."
x11vnc -display "${DISPLAY}" -forever -shared -rfbport "${VNC_PORT}" -nopw -noxdamage -xkb &

# Open a terminal on startup so users see something immediately
xfce4-terminal --geometry=120x35 --working-directory=/workspace &

echo "[ubuntu-desktop] Desktop ready - VNC on port ${VNC_PORT}"

# Run sshd as PID 1 for container lifecycle
exec /usr/sbin/sshd -D -e
