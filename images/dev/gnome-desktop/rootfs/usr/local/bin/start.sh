#!/bin/bash
set -e

DISPLAY="${DISPLAY:-:99}"
RESOLUTION="${RESOLUTION:-1920x1080x24}"
VNC_PORT="${VNC_PORT:-5900}"

echo "[gnome-desktop] Starting Xvfb on ${DISPLAY} at ${RESOLUTION}..."
Xvfb "${DISPLAY}" -screen 0 "${RESOLUTION}" -ac +extension GLX +render -noreset &
XVFB_PID=$!

# Wait for display to be ready
for i in $(seq 1 30); do
    if xdpyinfo -display "${DISPLAY}" >/dev/null 2>&1; then
        echo "[gnome-desktop] Display ${DISPLAY} ready"
        break
    fi
    if [ "$i" -eq 30 ]; then
        echo "[gnome-desktop] ERROR: Display ${DISPLAY} failed to start"
        exit 1
    fi
    sleep 0.2
done

# Start dbus session (required for GNOME)
export $(dbus-launch)
echo "[gnome-desktop] D-Bus session started"

# Apply dark theme and Yaru icon theme via gsettings
gsettings set org.gnome.desktop.interface gtk-theme 'Yaru-dark' 2>/dev/null || true
gsettings set org.gnome.desktop.interface icon-theme 'Yaru' 2>/dev/null || true
gsettings set org.gnome.desktop.interface font-name 'Noto Sans 10' 2>/dev/null || true
gsettings set org.gnome.desktop.interface monospace-font-name 'DejaVu Sans Mono 11' 2>/dev/null || true
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' 2>/dev/null || true
gsettings set org.gnome.desktop.background picture-options 'none' 2>/dev/null || true
gsettings set org.gnome.desktop.background primary-color '#2c001e' 2>/dev/null || true

# Configure GNOME Terminal dark profile
gsettings set org.gnome.Terminal.Legacy.Settings theme-variant 'dark' 2>/dev/null || true

echo "[gnome-desktop] Starting GNOME Flashback (Metacity) session..."
# Start metacity window manager
metacity --display="${DISPLAY}" --sm-disable &
sleep 1

# Start GNOME panel
gnome-panel &
sleep 1

echo "[gnome-desktop] Starting x11vnc on port ${VNC_PORT}..."
x11vnc -display "${DISPLAY}" -forever -shared -rfbport "${VNC_PORT}" -nopw -noxdamage -xkb &

# Open a terminal on startup
gnome-terminal --geometry=120x35 -- bash -c 'cd /workspace && exec bash' &

echo "[gnome-desktop] Desktop ready - VNC on port ${VNC_PORT}"

# Run sshd as PID 1 for container lifecycle
exec /usr/sbin/sshd -D -e
