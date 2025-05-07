#!/usr/bin/env bash
set -euo pipefail

# ─── 0) Required ENV ───────────────────────────────────────────────────────────
: "${RESOLUTION:?Need RESOLUTION (e.g. 1280x720)}"
: "${FPS:=30}"
: "${STREAM_URL:?Need STREAM_URL (rtmps://…)}"
: "${STREAM_KEY:?Need STREAM_KEY}"
: "${TARGET_URL:?Need TARGET_URL (http://localhost:8080/chart.html)}"
: "${BITRATE:=2500k}"
: "${BUF_SIZE:=512k}"

# ─── 1) Cleanup ────────────────────────────────────────────────────────────────
pkill Xvfb        >/dev/null 2>&1 || true
rm -rf /tmp/.X99-lock /tmp/chrome-profile /tmp/runtime-root

# ─── 2) DBus setup ─────────────────────────────────────────────────────────────
mkdir -p /run/dbus
dbus-daemon --system --fork --print-address
if command -v dbus-launch >/dev/null; then
    eval "$(dbus-launch --sh-syntax --exit-with-session)"
    export DBUS_SESSION_BUS_ADDRESS
fi

# ─── 3) Disable Chrome "Default browser" prompt ────────────────────────────────
mkdir -p /etc/opt/chrome/policies/managed
cat >/etc/opt/chrome/policies/managed/disable_default_browser_prompt.json <<EOF
{ "DefaultBrowserPromptEnabled": false }
EOF

# ─── 4) Parse dimensions & prepare X ───────────────────────────────────────────
export XDG_RUNTIME_DIR=/tmp/runtime-root
mkdir -p "$XDG_RUNTIME_DIR" && chmod 700 "$XDG_RUNTIME_DIR"

WIDTH="${RESOLUTION%x*}"
HEIGHT="${RESOLUTION#*x}"

# ─── 5) Launch virtual display + WM ────────────────────────────────────────────
Xvfb :99 -screen 0 "${WIDTH}x${HEIGHT}x24" &
export DISPLAY=:99
fluxbox -display :99 >/dev/null 2>&1 &

# Wait for display to be ready
for i in {1..20}; do
  xdpyinfo -display "$DISPLAY" >/dev/null 2>&1 && break
  sleep 0.2
done

# ─── 6) Serve static chart.html ────────────────────────────────────────────────
(
  cd /app/html
  exec python3 -u -m http.server 8080
) &

# ─── 7) Launch Chrome ──────────────────────────────────────────────────────────
export CHROME_USER_DATA=/tmp/chrome-profile
rm -rf "$CHROME_USER_DATA"
mkdir -p "$CHROME_USER_DATA"

google-chrome-stable \
  --no-sandbox --disable-setuid-sandbox \
  --disable-dev-shm-usage \
  --user-data-dir="$CHROME_USER_DATA" \
  --app="$TARGET_URL" \
  --kiosk --start-fullscreen \
  --window-size="${WIDTH},${HEIGHT}" \
  --disable-gpu --enable-software-rasterizer \
  --use-gl=swiftshader \
  --incognito --disable-infobars \
  --disable-features=TranslateUI,DefaultBrowserUI \
  --disable-extensions --no-first-run \
  > /tmp/chrome.log 2>&1 &

# ─── 8) Wait for chart page to load ────────────────────────────────────────────
echo "→ waiting for ${TARGET_URL} …"
until curl -fs --max-time 2 "$TARGET_URL" >/dev/null; do
  sleep 1
done

# ─── 9) Probe screen (render check) ────────────────────────────────────────────
echo "→ probing first rendered frame…"
mkdir -p /tmp
for i in {1..30}; do
  ffmpeg -y -loglevel error \
    -f x11grab -video_size "${WIDTH}x${HEIGHT}" -i "${DISPLAY}" \
    -frames:v 1 /tmp/render_check.png

  if [ "$(stat -c%s /tmp/render_check.png)" -gt 20000 ]; then
    echo "→ chart painted!"
    break
  fi
  sleep 1
done

# ─── 10) Screenshot loop for debugging ─────────────────────────────────────────
mkdir -p /app/screenshots
(
  while true; do
    shot="/app/screenshots/$(date +%Y%m%d_%H%M%S).png"
    ffmpeg -y -loglevel error \
      -f x11grab -video_size "${WIDTH}x${HEIGHT}" -i "${DISPLAY}" \
      -frames:v 1 "$shot" && echo "📸 $shot"
    sleep 10
  done
) &

# ─── 11) Start stream ──────────────────────────────────────────────────────────
echo "→ Starting live stream to: ${STREAM_URL}/${STREAM_KEY}"
exec ffmpeg \
  -thread_queue_size 512 \
  -probesize 10M -analyzeduration 10M \
  -f x11grab -framerate "${FPS}" \
      -video_size "${WIDTH}x${HEIGHT}" -i "${DISPLAY}" \
  -f lavfi -i anullsrc=channel_layout=stereo:sample_rate=44100 \
  -c:v libx264 -preset veryfast \
      -b:v "${BITRATE}" -maxrate "${BITRATE}" -bufsize "${BUF_SIZE}" \
      -g $((FPS * 2)) -pix_fmt yuv420p \
  -c:a aac -b:a 128k -ar 44100 \
  -f flv "${STREAM_URL}/${STREAM_KEY}"
