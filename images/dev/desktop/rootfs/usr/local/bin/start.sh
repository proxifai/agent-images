#!/bin/bash
set -e

DISPLAY="${DISPLAY:-:99}"
RESOLUTION="${RESOLUTION:-1920x1080x24}"
VNC_PORT="${VNC_PORT:-5900}"

echo "[desktop] Starting Xvfb on ${DISPLAY} at ${RESOLUTION}..."
Xvfb "${DISPLAY}" -screen 0 "${RESOLUTION}" -ac +extension GLX +render -noreset &
XVFB_PID=$!

# Wait for display to be ready
for i in $(seq 1 30); do
    if xdpyinfo -display "${DISPLAY}" >/dev/null 2>&1; then
        echo "[desktop] Display ${DISPLAY} ready"
        break
    fi
    if [ "$i" -eq 30 ]; then
        echo "[desktop] ERROR: Display ${DISPLAY} failed to start"
        exit 1
    fi
    sleep 0.2
done

# Set a dark wallpaper color
xsetroot -display "${DISPLAY}" -solid '#1e1e2e'

echo "[desktop] Starting Openbox window manager..."
openbox --sm-disable &

echo "[desktop] Starting x11vnc on port ${VNC_PORT}..."
x11vnc -display "${DISPLAY}" -forever -shared -rfbport "${VNC_PORT}" -nopw -noxdamage -xkb &

# Launch an initial xterm so users see something on connect
xterm -geometry 120x35+100+100 -fa 'DejaVu Sans Mono' -fs 11 &

echo "[desktop] Desktop ready - VNC on port ${VNC_PORT}"

# Run sshd as PID 1 for container lifecycle
exec /usr/sbin/sshd -D -e
