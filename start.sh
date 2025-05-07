#!/bin/bash
set -e

# ─────────────────────────────────────────────────────────────────────────────
# 0) Disable Chrome "make default browser" prompt via enterprise policy
mkdir -p /etc/opt/chrome/policies/managed
cat <<'EOF' >/etc/opt/chrome/policies/managed/disable_default_browser_prompt.json
{
  "DefaultBrowserPromptEnabled": false
}
EOF

# 0.1) Cleanup any stale Xvfb
pkill Xvfb           || true
rm -f /tmp/.X99-lock

# 0.2) Prepare XDG_RUNTIME_DIR (needed by Chrome)
export XDG_RUNTIME_DIR=/tmp/runtime-root
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"
# ─────────────────────────────────────────────────────────────────────────────

# 1) Parse RESOLUTION into WIDTH and HEIGHT (expects "1280x720")
WIDTH="${RESOLUTION%x*}"
HEIGHT="${RESOLUTION#*x}"

# 2) Start virtual X display
Xvfb :99 -screen 0 "${WIDTH}x${HEIGHT}x24" &
export DISPLAY=:99

# 3) Launch a D-Bus session for Chrome
eval "$(dbus-launch --sh-syntax --exit-with-session)"
export DBUS_SYSTEM_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS"

# 4) Serve your chart.html on localhost:8080
( cd /app/html && python3 -m http.server 8080 ) &
# ─── start.sh excerpt ────────────────────────────────────────────────────────

# 3) Prepare an empty profile dir so Chrome won't fall back to your system defaults:
export CHROME_USER_DATA=/tmp/chrome-profile
rm -rf "${CHROME_USER_DATA}"
mkdir -p "${CHROME_USER_DATA}"

# 4) Launch Chrome “app”/kiosk mode using that clean profile and disable every
#    default-browser check/promt feature:
google-chrome-stable \
  --user-data-dir="${CHROME_USER_DATA}" \
  --no-first-run \
  --no-default-browser-check \
  --disable-default-apps \
  --disable-infobars \
  --disable-features=DefaultBrowserUI,DefaultBrowserPromo \
  --kiosk \
  --window-size=${WIDTH},${HEIGHT} \
  "${TARGET_URL}" &
  

# Give Chrome & TradingView a moment to fully render
sleep 15

# 6) Background screenshot loop (for debugging) every 10s
mkdir -p /app/screenshots
while true; do
  google-chrome-stable \
    --no-sandbox \
    --headless \
    --no-default-browser-check \
    --disable-first-run-ui \
    --disable-default-apps \
    --disable-infobars \
    --disable-features=DefaultBrowserUI \
    --enable-webgl \
    --use-gl=swiftshader \
    --enable-unsafe-swiftshader \
    --disable-dev-shm-usage \
    --ignore-certificate-errors \
    --virtual-time-budget=10000 \
    --window-size=${WIDTH},${HEIGHT} \
    --screenshot="/app/screenshots/$(date +%Y%m%d_%H%M%S).png" \
    "${TARGET_URL}"
  sleep 10
done &

# 7) Capture & push to YouTube Live at ${FPS}fps with silent audio
echo "→ Streaming to: ${STREAM_URL}/${STREAM_KEY}"
ffmpeg \
  -f x11grab \
    -probesize 50M -analyzeduration 100M -thread_queue_size 512 \
    -framerate "${FPS}" -video_size "${WIDTH}x${HEIGHT}" -i :99.0 \
  -f lavfi -i anullsrc=channel_layout=stereo:sample_rate=44100 \
  -c:v libx264 -preset veryfast -b:v 2500k -maxrate 2500k -bufsize 512k \
  -g "$((FPS*2))" \
  -c:a aac -b:a 128k -ar 44100 \
  -shortest \
  -f flv "${STREAM_URL}/${STREAM_KEY}"
