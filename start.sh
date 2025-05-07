#!/usr/bin/env bash
set -Eeuo pipefail

################################################################################
#  CONFIG (all overridable via .env / docker‑compose)                           #
################################################################################
: "${RESOLUTION:=1280x720}"
: "${FPS:=30}"
: "${CBR:=2500k}"                 # ← 1500k or 2500k typical for 720p
: "${STREAM_URL:?need STREAM_URL}"
: "${STREAM_KEY:?need STREAM_KEY}"
: "${TARGET_URL:?need TARGET_URL}"
: "${THREAD_QUEUE:=512}"          # Raise if “queue blocking” persists
: "${HEALTH_PORT:=8890}"          # Where we expose the TCP probe

WIDTH=${RESOLUTION%x*}; HEIGHT=${RESOLUTION#*x}
export DISPLAY=:99
export XDG_RUNTIME_DIR=/tmp/runtime
mkdir -p "$XDG_RUNTIME_DIR" /run/dbus

################################################################################
#  UTILITIES                                                                   #
################################################################################
log()   { printf '\e[32m[%s] %s\e[0m\n' "$(date '+%H:%M:%S')" "$*"; }
err()   { printf '\e[31m[%s] %s\e[0m\n' "$(date '+%H:%M:%S')" "$*" >&2; }
die()   { err "$*"; exit 1; }

cleanup() {
  pkill -TERM Xvfb  openbox google-chrome-stable ffmpeg || true
}
trap cleanup EXIT INT TERM

################################################################################
#  1) System & session D‑Bus                                                   #
################################################################################
dbus-daemon --system --fork --print-address
# A session bus is optional but silences warnings
if command -v dbus-launch &>/dev/null; then
  eval "$(dbus-launch --exit-with-session --sh-syntax)"
fi

################################################################################
#  2) Xvfb + WM                                                                #
################################################################################
log "Starting Xvfb ${WIDTH}x${HEIGHT}…"
Xvfb $DISPLAY -screen 0 "${WIDTH}x${HEIGHT}x24" 2>&1 &
for i in {1..30}; do xdpyinfo -display $DISPLAY &>/dev/null && break; sleep 0.1; done
openbox &

################################################################################
#  3) Static HTTP server for local assets                                      #
################################################################################
( cd /app/html && python3 -m http.server 8080 --bind 0.0.0.0 ) &
log "Local HTTP server on :8080"

################################################################################
#  4) Launch Chrome (software raster)                                          #
################################################################################
log "Launching Chrome → $TARGET_URL"
google-chrome-stable \
  --no-sandbox --disable-setuid-sandbox \
  --disable-dev-shm-usage --disable-gpu \
  --use-gl=swiftshader --enable-software-rasterizer \
  --user-data-dir=/tmp/chrome --app="$TARGET_URL" \
  --kiosk --window-size="${WIDTH},${HEIGHT}" \
  --no-first-run --disable-features=TranslateUI,DefaultBrowserUI \
  --disable-extensions --mute-audio > /tmp/chrome.log 2>&1 &

################################################################################
#  5) Wait until page paints (probe pixel change)                              #
################################################################################
for s in {1..20}; do
  if ffmpeg -v quiet -f x11grab -video_size "${WIDTH}x${HEIGHT}" -frames 1 \
        -i "$DISPLAY" -f crc -; then
    log "Display live after ${s}s"
    break
  fi
  sleep 1
done || die "Chrome never painted the page!"

################################################################################
#  6) Health end‑point for orchestrator                                        #
################################################################################
( while true; do echo -e "HTTP/1.1 200 OK\r\n\r\nhealthy" | nc -l -p 8890 -q 0; done ) &
command -v nc >/dev/null || die "netcat not found; install netcat-openbsd"

log "Exposing health probe on :$HEALTH_PORT"
( while true; do
    { printf 'HTTP/1.1 200 OK\r\n\r\nhealthy'; } \
      | nc -l -p "$HEALTH_PORT" -q 0
  done ) &
################################################################################
#  7) Run FFmpeg with *true* CBR                                               #
################################################################################
log "Streaming @ ${CBR} CBR → ${STREAM_URL}/${STREAM_KEY}"
exec ffmpeg -loglevel warning -re \
  -thread_queue_size "$THREAD_QUEUE" \
  -f x11grab -video_size "${WIDTH}x${HEIGHT}" -framerate "$FPS" -i "$DISPLAY" \
  -f lavfi -i anullsrc=channel_layout=stereo:sample_rate=44100 \
  -c:v libx264 -preset veryfast \
      -b:v "$CBR" -minrate "$CBR" -maxrate "$CBR" \
      -bufsize "$CBR" -x264-params "nal-hrd=cbr:force-cfr=1" \
      -pix_fmt yuv420p -g $((FPS*2)) \
  -c:a aac -b:a 128k -ar 44100 \
  -f flv "${STREAM_URL}/${STREAM_KEY}"