#!/bin/bash
set -e

# One container, N screens.
#
# A bot machine is shared: several bots ride the same box, each driving its own
# desktop, so this starts SCREENS independent stacks instead of one. Screen n is
# display :(BASE_DISPLAY+n), served over VNC on (BASE_VNC_PORT+n), with Chromium
# listening for DevTools Protocol on (CDP_BASE_PORT+n) — the same arithmetic as
# models.DisplayForScreen / models.VNCPortForScreen in the platform.
#
# Screen 0 therefore lands on :99 / 5900 / 9222, which is what the platform's
# instance tools expect by default.
#
# SCREENS=1 (the default, and what a dedicated machine always gets) reproduces
# the single-desktop behaviour exactly.
SCREENS="${SCREENS:-1}"
BASE_DISPLAY="${BASE_DISPLAY:-99}"
BASE_VNC_PORT="${BASE_VNC_PORT:-5900}"
CDP_BASE_PORT="${CDP_BASE_PORT:-9222}"
RESOLUTION="${RESOLUTION:-1920x1080x24}"
LAUNCH_BROWSER="${LAUNCH_BROWSER:-1}"
BROWSER_HOME_PAGE="${BROWSER_HOME_PAGE:-about:blank}"
COMPOSITOR="${COMPOSITOR:-1}"
USER_NAME="user"

case "$SCREENS" in
    ''|*[!0-9]*) echo "[desktop] SCREENS must be a number, got '${SCREENS}'"; exit 1 ;;
esac
if [ "$SCREENS" -lt 1 ]; then SCREENS=1; fi

# DISPLAY/VNC_PORT are still honoured for a single screen, so existing callers
# that set them keep working.
if [ "$SCREENS" -eq 1 ] && [ -n "${DISPLAY:-}" ]; then
    BASE_DISPLAY="${DISPLAY#:}"
fi
if [ "$SCREENS" -eq 1 ] && [ -n "${VNC_PORT:-}" ]; then
    BASE_VNC_PORT="${VNC_PORT}"
fi

start_screen() {
    local index="$1"
    local display=":$((BASE_DISPLAY + index))"
    local vnc_port=$((BASE_VNC_PORT + index))
    local cdp_port=$((CDP_BASE_PORT + index))

    echo "[desktop] screen ${index}: Xvfb on ${display} at ${RESOLUTION}"
    Xvfb "${display}" -screen 0 "${RESOLUTION}" -ac +extension GLX +render -noreset &

    for i in $(seq 1 30); do
        if xdpyinfo -display "${display}" >/dev/null 2>&1; then
            echo "[desktop] screen ${index}: display ${display} ready"
            break
        fi
        if [ "$i" -eq 30 ]; then
            echo "[desktop] ERROR: screen ${index}: display ${display} failed to start"
            exit 1
        fi
        sleep 0.2
    done

    xsetroot -display "${display}" -solid '#1e1e2e'

    # The session body lives in its own script. Inlining it into su -c meant any
    # double quote in the body -- including one inside a comment -- silently
    # truncated the command and left the desktop empty, which is precisely how
    # the machine ended up showing a blank dark screen.
    #
    # Screens share the filesystem and the user account by design: they are
    # separate work surfaces, not a security boundary, and the system prompt
    # tells the bots so.
    su -l "${USER_NAME}" -s /bin/bash -c \
        "DISPLAY='${display}' \
         VNC_PORT_FOR_SCREEN='${vnc_port}' \
         CDP_PORT_FOR_SCREEN='${cdp_port}' \
         LAUNCH_BROWSER='${LAUNCH_BROWSER}' \
         BROWSER_HOME_PAGE='${BROWSER_HOME_PAGE}' \
         COMPOSITOR='${COMPOSITOR}' \
         /usr/local/bin/screen-session.sh ${index}" &
}

# Allow the user to reach every X display we are about to create.
xhost +local: >/dev/null 2>&1 || true

screen=0
while [ "$screen" -lt "$SCREENS" ]; do
    start_screen "$screen"
    screen=$((screen + 1))
done

echo "[desktop] ready -- ${SCREENS} screen(s); VNC ${BASE_VNC_PORT}..$((BASE_VNC_PORT + SCREENS - 1)); CDP ${CDP_BASE_PORT}..$((CDP_BASE_PORT + SCREENS - 1))"

# Run sshd as PID 1 for container lifecycle
exec /usr/sbin/sshd -D -e
