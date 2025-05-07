# syntax=docker/dockerfile:1.4
FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive

# ── Bootstrap tools & DBus ────────────────────────────────────────────────
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        wget curl gnupg ca-certificates apt-transport-https \
        dbus dbus-user-session dbus-x11 \
        && rm -rf /var/lib/apt/lists/*

# ── Google Chrome repo (binary keyring) ───────────────────────────────────
RUN curl -fsSL https://dl.google.com/linux/linux_signing_key.pub \
       | gpg --dearmor -o /usr/share/keyrings/google-linux.gpg && \
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-linux.gpg] \
         https://dl.google.com/linux/chrome/deb/ stable main" \
       > /etc/apt/sources.list.d/google-chrome.list

# ── Final runtime stack ───────────────────────────────────────────────────
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        google‑chrome‑stable=1:latest \
        xvfb openbox \
        libnss3 libxss1 libatk-bridge2.0-0 libgtk-3-0 \
        libgbm1 libasound2 libunwind8 libdbus-1-3 \
        ffmpeg python3 \
        netcat-openbsd \
        fonts-dejavu-core fonts-liberation \
        && rm -rf /var/lib/apt/lists/*
RUN --mount=type=cache,target=/var/cache/apt
WORKDIR /app
COPY html        ./html
COPY start.sh    ./start.sh
RUN chmod +x ./start.sh

# — A simple TCP health‑probe: ffmpeg listens on 127.0.0.1:8890 when alive —
HEALTHCHECK CMD curl -fs http://127.0.0.1:8890/health || exit 1

ENTRYPOINT ["./start.sh"]
