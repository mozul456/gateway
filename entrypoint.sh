#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# IRL Streaming Gateway - EntryPoint
# ============================================================
# Responsabilidades:
# - Comprobar dependencias
# - Iniciar MediaMTX
# - Iniciar Xvfb + Chromium para overlays HTML
# - Iniciar switcher.py (GStreamer + lógica)
# - Supervisar procesos y reiniciarlos si fallan
# - Finalizar correctamente al detener el contenedor
# ============================================================

cd /home/container

# ------------------------------------------------------------
# Variables de entorno
# ------------------------------------------------------------

: "${SRT_PORT:=9000}"
: "${RTMP_PORT:=1935}"
: "${OUTPUT_URL:=rtmps://live.kick.com/app}"
: "${OUTPUT_KEY:=}"
: "${VIDEO_BITRATE:=4000000}"
: "${AUDIO_BITRATE:=128000}"
: "${WIDTH:=1280}"
: "${HEIGHT:=720}"
: "${FPS:=30}"
: "${FALLBACK_VIDEO:=/home/container/fallback/video.mp4}"
: "${OVERLAY_ENABLED:=1}"
: "${OVERLAY_URL:=file:///home/container/overlay/index.html}"

export SRT_PORT RTMP_PORT OUTPUT_URL OUTPUT_KEY
export VIDEO_BITRATE AUDIO_BITRATE WIDTH HEIGHT FPS
export FALLBACK_VIDEO OVERLAY_ENABLED OVERLAY_URL

mkdir -p /home/container/logs

echo "=================================================="
echo " IRL Streaming Gateway"
echo "=================================================="
echo "SRT_PORT=$SRT_PORT"
echo "RTMP_PORT=$RTMP_PORT"
echo "OUTPUT_URL=$OUTPUT_URL"
echo "VIDEO_BITRATE=$VIDEO_BITRATE"
echo "AUDIO_BITRATE=$AUDIO_BITRATE"
echo "WIDTH=$WIDTH"
echo "HEIGHT=$HEIGHT"
echo "FPS=$FPS"
echo "OVERLAY_ENABLED=$OVERLAY_ENABLED"
echo "OVERLAY_URL=$OVERLAY_URL"
echo "=================================================="

# ------------------------------------------------------------
# Comprobar binarios necesarios
# ------------------------------------------------------------

echo "[Check] Verificando dependencias..."

REQUIRED_BINS=(
    python3
    Xvfb
    chromium
)

for BIN in "${REQUIRED_BINS[@]}"; do
    if ! command -v "$BIN" >/dev/null 2>&1; then
        echo "ERROR: No se encontró '$BIN' en el PATH"
        exit 1
    fi

    echo "OK: $BIN -> $(command -v "$BIN")"
done

if [ ! -x /usr/local/bin/mediamtx ]; then
    echo "ERROR: No existe /usr/local/bin/mediamtx"
    exit 1
fi

echo "OK: MediaMTX -> /usr/local/bin/mediamtx"

# ------------------------------------------------------------
# Comprobar configuración
# ------------------------------------------------------------

if [ ! -f /home/container/mediamtx.yml ]; then
    echo "ERROR: No existe /home/container/mediamtx.yml"
    exit 1
fi

echo "OK: Configuración MediaMTX encontrada"

# ------------------------------------------------------------
# Variables de PIDs
# ------------------------------------------------------------

MEDIAMTX_PID=""
SWITCHER_PID=""
XVFB_PID=""
CHROMIUM_PID=""

# ------------------------------------------------------------
# Finalización limpia
# ------------------------------------------------------------

cleanup() {

    echo
    echo "[EntryPoint] Deteniendo procesos..."

    for PID in \
        "$CHROMIUM_PID" \
        "$XVFB_PID" \
        "$SWITCHER_PID" \
        "$MEDIAMTX_PID"
    do
        if [[ -n "$PID" ]] && kill -0 "$PID" 2>/dev/null; then
            kill "$PID" 2>/dev/null || true
            wait "$PID" 2>/dev/null || true
        fi
    done

    echo "[EntryPoint] Todos los procesos detenidos."
    exit 0
}

trap cleanup SIGTERM SIGINT EXIT

# ------------------------------------------------------------
# Iniciar MediaMTX
# ------------------------------------------------------------

echo "[EntryPoint] Iniciando MediaMTX..."

/usr/local/bin/mediamtx /home/container/mediamtx.yml &

MEDIAMTX_PID=$!

echo "[EntryPoint] MediaMTX PID: $MEDIAMTX_PID"

sleep 2

# ------------------------------------------------------------
# Iniciar Xvfb + Chromium
# ------------------------------------------------------------

if [[ "$OVERLAY_ENABLED" == "1" ]]; then

    export DISPLAY=:99

    XRES=$WIDTH
    YRES=$HEIGHT
    DEPTH=24

    echo "[EntryPoint] Iniciando Xvfb..."

    Xvfb "$DISPLAY" \
        -screen 0 "${XRES}x${YRES}x${DEPTH}" \
        -nolisten tcp &

    XVFB_PID=$!

    echo "[EntryPoint] Xvfb PID: $XVFB_PID"

    # Esperar a que Xvfb esté listo
    sleep 2

    echo "[EntryPoint] Iniciando Chromium..."

    chromium \
        --disable-gpu \
        --headless \
        --no-sandbox \
        --disable-dev-shm-usage \
        --hide-scrollbars \
        --autoplay-policy=no-user-gesture-required \
        --window-size="${WIDTH},${HEIGHT}" \
        --start-maximized \
        "$OVERLAY_URL" &

    CHROMIUM_PID=$!

    echo "[EntryPoint] Chromium PID: $CHROMIUM_PID"

else

    echo "[EntryPoint] Overlays deshabilitados"

fi

# ------------------------------------------------------------
# Iniciar switcher.py
# ------------------------------------------------------------

echo "[EntryPoint] Iniciando switcher.py..."

python3 /home/container/switcher.py &

SWITCHER_PID=$!

echo "[EntryPoint] switcher.py PID: $SWITCHER_PID"

echo
echo "=================================================="
echo " IRL Gateway iniciado correctamente"
echo "=================================================="

# ------------------------------------------------------------
# Supervisión
# ------------------------------------------------------------

while true; do

    sleep 5

    if ! kill -0 "$MEDIAMTX_PID" 2>/dev/null; then

        echo "[Monitor] MediaMTX detenido. Reiniciando..."

        /usr/local/bin/mediamtx /home/container/mediamtx.yml &

        MEDIAMTX_PID=$!

        echo "[Monitor] Nuevo PID MediaMTX: $MEDIAMTX_PID"
    fi

    if ! kill -0 "$SWITCHER_PID" 2>/dev/null; then

        echo "[Monitor] switcher.py detenido. Reiniciando..."

        python3 /home/container/switcher.py &

        SWITCHER_PID=$!

        echo "[Monitor] Nuevo PID switcher.py: $SWITCHER_PID"
    fi

    if [[ "$OVERLAY_ENABLED" == "1" ]]; then

        if ! kill -0 "$XVFB_PID" 2>/dev/null; then

            echo "[Monitor] Xvfb detenido. Reiniciando..."

            Xvfb "$DISPLAY" \
                -screen 0 "${XRES}x${YRES}x${DEPTH}" \
                -nolisten tcp &

            XVFB_PID=$!

            sleep 2

            echo "[Monitor] Nuevo PID Xvfb: $XVFB_PID"
        fi

        if ! kill -0 "$CHROMIUM_PID" 2>/dev/null; then

            echo "[Monitor] Chromium detenido. Reiniciando..."

            chromium \
                --disable-gpu \
                --headless \
                --no-sandbox \
                --disable-dev-shm-usage \
                --hide-scrollbars \
                --autoplay-policy=no-user-gesture-required \
                --window-size="${WIDTH},${HEIGHT}" \
                --start-maximized \
                "$OVERLAY_URL" &

            CHROMIUM_PID=$!

            echo "[Monitor] Nuevo PID Chromium: $CHROMIUM_PID"
        fi

    fi

done
