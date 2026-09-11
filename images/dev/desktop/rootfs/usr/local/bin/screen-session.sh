#!/bin/bash
# One screen's user session: window manager, compositor, VNC, terminal, browser.
#
# This lives in its own file rather than inside a `su -l user -c "..."` string
# on purpose. The string form breaks the moment the body contains a double
# quote — a COMMENT mentioning an "unsupported flag" was enough to terminate
# the argument early — and the failure mode is not an error but a desktop that
# comes up with nothing on it.
#
# Runs as `user` with DISPLAY already exported by the caller.
set -u

index="${1:-0}"

: "${DISPLAY:?screen-session: DISPLAY must be set by the caller}"
: "${HOME:=/home/user}"

VNC_PORT_FOR_SCREEN="${VNC_PORT_FOR_SCREEN:-5900}"
# Exported: the panel inherits it, so a browser started from the dock lands on
# the same debugging port as the one started here.
export CDP_PORT_FOR_SCREEN="${CDP_PORT_FOR_SCREEN:-9222}"
export SCREEN_INDEX="${index}"
LAUNCH_BROWSER="${LAUNCH_BROWSER:-1}"
BROWSER_HOME_PAGE="${BROWSER_HOME_PAGE:-about:blank}"
# Chrome is started MAXIMIZED rather than at an explicit size. An explicit
# --window-size=WxH is measured against the whole screen, so a full-height
# window sits on top of the dock and hides it. Maximised means xfwm4 places it
# inside the work area the panel reserves, and the dock stays visible — the
# same reason a maximised window on macOS stops above the Dock.
COMPOSITOR="${COMPOSITOR:-1}"

export XDG_RUNTIME_DIR="/tmp/runtime-$(id -un)-${index}"
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

# Fontconfig writes its cache here. Without a writable location every X client
# dies at startup with "No writable cache directories" and the desktop is bare.
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
mkdir -p "$XDG_CACHE_HOME/fontconfig"

# Each screen needs its own xfconf/dbus state, or the second session inherits
# the first one's settings daemon and the two fight over window decorations.
export XDG_CONFIG_HOME="$HOME/.config-screen-${index}"
mkdir -p "$XDG_CONFIG_HOME"

# Per-screen logs. Discarding stderr is what let a window manager fail on an
# unknown flag while the startup log still claimed it had started.
SESSION_LOG_DIR="/tmp/session-${index}"
mkdir -p "$SESSION_LOG_DIR"

# A per-screen session bus. xfwm4 and xfconf both expect one; without it they
# fall back to autolaunch, which spawns a bus per invocation and leaks.
if command -v dbus-launch >/dev/null 2>&1; then
    eval "$(dbus-launch --sh-syntax)" 2>/dev/null || true
    export DBUS_SESSION_BUS_ADDRESS DBUS_SESSION_BUS_PID
fi

echo "[screen ${index}] xfwm4"
# --replace so a restarted session takes over cleanly instead of exiting with
# "another window manager is already running".
#
# NOT --daemon: xfwm4 4.20 removed that flag and exits immediately with
# "Unknown option --daemon" — which looked exactly like a working start, since
# the log line had already been printed and stderr was discarded. Errors go to
# a log now rather than /dev/null for the same reason.
#
# --compositor=off hands compositing to picom. xfwm4 ships its own compositor
# and enables it by default, and two compositors cannot own one screen: picom
# exits with "Another composite manager is already running". Which one wins has
# to be chosen explicitly, and here it is picom.
if [ "$COMPOSITOR" = "1" ]; then
    xfwm4 --replace --compositor=off >"$SESSION_LOG_DIR/xfwm4.log" 2>&1 &
else
    # No picom: let xfwm4 composite, so windows still get shadows.
    xfwm4 --replace --compositor=on >"$SESSION_LOG_DIR/xfwm4.log" 2>&1 &
fi

# Give xfwm4 a moment to own the screen before the compositor and clients
# attach; picom bails out if it starts against a half-initialised WM.
sleep 1

if [ "$COMPOSITOR" = "1" ] && command -v picom >/dev/null 2>&1; then
    echo "[screen ${index}] picom"
    # picom 12 takes the display from $DISPLAY — it has no --display option and
    # refuses to start if given one. vsync is a boolean here (--no-vsync), not
    # the older --vsync=none.
    #
    # xrender, not glx: this is a virtual framebuffer with no GPU, so glx falls
    # back to slow software rendering. And there is no refresh cycle to sync
    # to, so vsync would only add latency to every frame the VNC client waits on.
    picom --backend xrender --no-vsync --no-fading-openclose \
        >"$SESSION_LOG_DIR/picom.log" 2>&1 &
fi

echo "[screen ${index}] x11vnc on ${VNC_PORT_FOR_SCREEN}"
x11vnc -display "$DISPLAY" -forever -shared -rfbport "$VNC_PORT_FOR_SCREEN" \
       -nopw -noxdamage -noshm -xkb >"$SESSION_LOG_DIR/x11vnc.log" 2>&1 &

# The dock: launchers plus a tasklist, centred at the bottom of the screen.
#
# Seeded per screen because xfconf state is per XDG_CONFIG_HOME, and two
# screens sharing one config would fight over panel geometry. The anchor
# position is rewritten from the ACTUAL screen size so the bar stays centred at
# any RESOLUTION rather than at the 1920x1080 the template was written for.
PANEL_CFG="$XDG_CONFIG_HOME/xfce4/xfconf/xfce-perchannel-xml"
if [ ! -f "$PANEL_CFG/xfce4-panel.xml" ] && [ -f /usr/local/share/proxifai/xfce4-panel.xml ]; then
    mkdir -p "$PANEL_CFG"
    screen_w=$(xdpyinfo | awk '/dimensions:/{split($2,d,"x"); print d[1]; exit}')
    screen_h=$(xdpyinfo | awk '/dimensions:/{split($2,d,"x"); print d[2]; exit}')
    sed "s|p=10;x=960;y=1080|p=10;x=$((screen_w / 2));y=${screen_h}|" \
        /usr/local/share/proxifai/xfce4-panel.xml > "$PANEL_CFG/xfce4-panel.xml"
fi

echo "[screen ${index}] xfce4-panel"
# --disable-wm-check: the panel otherwise waits for a window manager to announce
# itself in a way xfwm4 has already done by now, and gives up on a slow start.
xfce4-panel --disable-wm-check >"$SESSION_LOG_DIR/panel.log" 2>&1 &

# The visible terminal and the bot's character-level terminal_session tool are
# two clients of this SAME tmux session. A per-screen socket prevents bots on a
# shared machine from attaching to the wrong screen's console. Override only
# XDG_CONFIG_HOME for the shell inside tmux: XFCE keeps its isolated per-screen
# settings above, while OpenCode reads the managed ~/.config/opencode config.
/usr/local/bin/agent-terminal >"$SESSION_LOG_DIR/xterm.log" 2>&1 &

if [ "$LAUNCH_BROWSER" = "1" ]; then
    echo "[screen ${index}] google-chrome, CDP on ${CDP_PORT_FOR_SCREEN}"
    # SUPERVISED, not fire-and-forget. Chrome exiting — a crash, a renderer
    # failure, someone closing the last window — used to end the machine's
    # ability to browse for the rest of its life: nothing restarted it, and
    # browser_action can only attach to a port that is open. The bot's answer
    # was to ask the human to go run a shell command, which is the opposite of
    # navigating the web autonomously.
    #
    # The flags all live in agent-chrome so the dock icon and this loop start
    # the SAME browser.
    (
        export CDP_PORT_FOR_SCREEN SCREEN_INDEX="${index}"
        while true; do
            /usr/local/bin/agent-chrome "$BROWSER_HOME_PAGE" >>"$SESSION_LOG_DIR/chrome.log" 2>&1
            code=$?
            echo "[screen ${index}] chrome exited (${code}); restarting in 2s" \
                >>"$SESSION_LOG_DIR/chrome.log"
            # A tight respawn on a browser that cannot start would spin a core;
            # two seconds is invisible to a bot waiting on a page and cheap to
            # the machine.
            sleep 2
        done
    ) &
fi

# Report what actually survived. A component that dies on a bad flag used to
# leave no trace but an empty screen.
sleep 3
for proc in xfwm4 picom x11vnc xfce4-panel chrome; do
    if ! pgrep -x "$proc" >/dev/null 2>&1; then
        echo "[screen ${index}] WARNING: $proc is not running — $(tail -2 "$SESSION_LOG_DIR/${proc}.log" 2>/dev/null | tr '\n' ' ')"
    fi
done

wait
