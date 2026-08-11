#!/bin/bash
# Starts a virtual display (and optionally VNC), makes sure a factorio client is
# present, then hands the arguments to auto.py.
set -euo pipefail

log() { echo "[factoriomaps] $*"; }

FACTORIO_DIR="${FACTORIO_DIR:-/factorio}"
FACTORIO_BINARY="${FACTORIO_BINARY:-$FACTORIO_DIR/bin/x64/factorio}"
FACTORIO_USER_DIR="${FACTORIO_USER_DIR:-/data}"
FACTORIO_VERSION="${FACTORIO_VERSION:-latest}"

mkdir -p "$FACTORIO_USER_DIR/saves" "$FACTORIO_USER_DIR/mods" "$FACTORIO_USER_DIR/script-output"

# `shell` skips the client entirely, for poking at the image
SHELL_MODE=0
if [ "${1:-}" = "shell" ]; then
    SHELL_MODE=1
    shift
fi

# ---------------------------------------------------------------- factorio client
if [ "$SHELL_MODE" = "0" ] && [ ! -x "$FACTORIO_BINARY" ]; then
    if [ -z "${FACTORIO_USERNAME:-}" ] || [ -z "${FACTORIO_TOKEN:-}" ]; then
        cat >&2 <<'EOF'
[factoriomaps] No factorio client found and no credentials to download one.

The headless build cannot render, so the full client is required. Either:
  * mount an extracted client at /factorio, or
  * set FACTORIO_USERNAME and FACTORIO_TOKEN (from your player-data.json)
    so it can be downloaded into the /factorio volume once.
EOF
        exit 1
    fi
    log "downloading factorio $FACTORIO_VERSION client"
    mkdir -p "$FACTORIO_DIR"
    # the archive contains a top level factorio/ directory
    curl -fsSL -o /tmp/factorio.tar.xz \
        "https://factorio.com/get-download/${FACTORIO_VERSION}/alpha/linux64?username=${FACTORIO_USERNAME}&token=${FACTORIO_TOKEN}"
    tar -xJf /tmp/factorio.tar.xz -C "$FACTORIO_DIR" --strip-components=1
    rm -f /tmp/factorio.tar.xz
    log "client installed: $("$FACTORIO_BINARY" --version | head -1)"
fi

# Space Age ships separately. Saves that use it will not load without it, and
# factorio then blocks on a "mods to be disabled" prompt that nothing can answer.
if [ "${FACTORIO_EXPANSION:-1}" = "1" ] && [ -d "$FACTORIO_DIR/data" ] && [ ! -d "$FACTORIO_DIR/data/space-age" ]; then
    if [ -n "${FACTORIO_USERNAME:-}" ] && [ -n "${FACTORIO_TOKEN:-}" ]; then
        log "downloading space age expansion"
        if curl -fsSL -o /tmp/expansion.tar.xz \
            "https://factorio.com/get-download/${FACTORIO_VERSION}/expansion/linux64?username=${FACTORIO_USERNAME}&token=${FACTORIO_TOKEN}"; then
            tar -xJf /tmp/expansion.tar.xz -C "$FACTORIO_DIR" --strip-components=1
            log "expansion installed"
        else
            log "expansion not available on this account, continuing without it"
        fi
        rm -f /tmp/expansion.tar.xz
    fi
fi

# the mod itself lives in the image, factorio loads it from the mods folder
ln -sfn /opt/factoriomaps "$FACTORIO_USER_DIR/mods/L0laapk3_FactorioMaps"

# auto.py starts factorio with an explicit --config, which makes it ignore
# config-path.cfg and fall back to system data directories. seed a config with
# the real paths so it can find its own data.
if [ ! -f "$FACTORIO_USER_DIR/config/config.ini" ] && [ -d "$FACTORIO_DIR/data" ]; then
    log "seeding config.ini with the client data path"
    cat > "$FACTORIO_USER_DIR/config/config.ini" <<EOF
; version=3
[path]
read-data=$FACTORIO_DIR/data
write-data=$FACTORIO_USER_DIR
EOF
fi

# factorio resolves its user data relative to the binary unless told otherwise,
# so link the mounted directories into place
if [ -d "$FACTORIO_DIR" ]; then
    for dir in saves mods script-output config; do
        mkdir -p "$FACTORIO_USER_DIR/$dir"
        rm -rf "${FACTORIO_DIR:?}/$dir"
        ln -sfn "$FACTORIO_USER_DIR/$dir" "$FACTORIO_DIR/$dir"
    done
fi

# ---------------------------------------------------------------- display
log "starting Xvfb on $DISPLAY (${SCREEN_SIZE})"
# xvfb spends its first seconds complaining about keysyms it cannot resolve
Xvfb "$DISPLAY" -screen 0 "$SCREEN_SIZE" -nolisten tcp -noreset >/dev/null 2>&1 &
XVFB_PID=$!
for _ in $(seq 1 50); do
    xdpyinfo -display "$DISPLAY" >/dev/null 2>&1 && break
    sleep 0.2
done

cleanup() {
    kill "$XVFB_PID" 2>/dev/null || true
    [ -n "${VNC_PID:-}" ] && kill "$VNC_PID" 2>/dev/null || true
    [ -n "${NOVNC_PID:-}" ] && kill "$NOVNC_PID" 2>/dev/null || true
}
trap cleanup EXIT

if [ "${ENABLE_VNC:-0}" = "1" ]; then
    log "starting VNC on :${VNC_PORT} and noVNC on :${NOVNC_PORT}"
    x11vnc -display "$DISPLAY" -rfbport "$VNC_PORT" -forever -shared -nopw -quiet -bg >/dev/null 2>&1 &
    VNC_PID=$!
    websockify --web=/usr/share/novnc "$NOVNC_PORT" "localhost:$VNC_PORT" >/dev/null 2>&1 &
    NOVNC_PID=$!
fi

# ---------------------------------------------------------------- renderer
# Xvfb has no DRI, so plain GLX always resolves to llvmpipe. VirtualGL renders
# on the GPU through EGL instead, which is what makes captures fast.
LAUNCH_BINARY="$FACTORIO_BINARY"
if [ -e /dev/dri/renderD128 ] && [ "${LIBGL_ALWAYS_SOFTWARE:-0}" != "1" ] && command -v vglrun >/dev/null; then
    VGL_RENDERER=$(vglrun -d "${VGL_DISPLAY:-egl0}" glxinfo -B 2>/dev/null | grep -i "OpenGL renderer" | cut -d: -f2- | xargs || true)
    if [ -n "$VGL_RENDERER" ] && ! echo "$VGL_RENDERER" | grep -qi "llvmpipe\|softpipe"; then
        # the wrapper lives beside the real binary so factorio still finds its data directory
        LAUNCH_BINARY="$(dirname "$FACTORIO_BINARY")/factorio-vgl"
        cat > "$LAUNCH_BINARY" <<EOF
#!/bin/bash
exec vglrun -d ${VGL_DISPLAY:-egl0} "$FACTORIO_BINARY" "\$@"
EOF
        chmod +x "$LAUNCH_BINARY"
        log "renderer: $VGL_RENDERER (hardware, via VirtualGL)"
    else
        log "GPU present but VirtualGL did not get hardware acceleration, using llvmpipe"
    fi
fi
if [ "$LAUNCH_BINARY" = "$FACTORIO_BINARY" ]; then
    log "renderer: $(glxinfo -B 2>/dev/null | grep -i 'OpenGL renderer' | cut -d: -f2- | xargs || echo unknown) - expect slow captures"
fi

# ---------------------------------------------------------------- run
if [ "$SHELL_MODE" = "1" ]; then
    if [ "$#" -eq 0 ]; then
        exec bash
    fi
    exec "$@"
fi

cd /opt/factoriomaps

# Every auto.py flag can be passed straight to the container. FACTORIOMAPS_ARGS
# is a convenience for compose and cron, where overriding the command is
# awkward; anything given on the command line is appended after it and wins.
ARGS=()
if [ -n "${FACTORIOMAPS_ARGS:-}" ]; then
    read -r -a ENV_ARGS <<< "$FACTORIOMAPS_ARGS"
    ARGS+=("${ENV_ARGS[@]}")
fi
ARGS+=("$@")

log "auto.py ${ARGS[*]}"

set -o pipefail
if [ "${LOG_TIMESTAMPS:-1}" = "1" ]; then
    /opt/venv/bin/python -u auto.py \
        --factorio "$LAUNCH_BINARY" \
        --output-path "$FACTORIO_USER_DIR/script-output/FactorioMaps" \
        --mod-path "$FACTORIO_USER_DIR/mods" \
        --config-path "$FACTORIO_USER_DIR/config" \
        "${ARGS[@]}" 2>&1 | gawk '
            # library chatter on stderr, which never reaches auto.py s log handling
            /libpng warning:|XDG_RUNTIME_DIR|_XSERVTransmkdir|Could not resolve keysym|xkbcomp/ { next }
            { print strftime("%H:%M:%S"), $0; fflush() }'
    exit "${PIPESTATUS[0]}"
fi
exec /opt/venv/bin/python -u auto.py \
    --factorio "$LAUNCH_BINARY" \
    --output-path "$FACTORIO_USER_DIR/script-output/FactorioMaps" \
    --mod-path "$FACTORIO_USER_DIR/mods" \
    --config-path "$FACTORIO_USER_DIR/config" \
    "${ARGS[@]}"
