# syntax=docker/dockerfile:1.4
FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive

### 0) Bootstrap tools
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        wget curl gnupg ca-certificates apt-transport-https dbus && \
    rm -rf /var/lib/apt/lists/*

### 1) Google Chrome: key + repo
RUN curl -fsSL https://dl.google.com/linux/linux_signing_key.pub | \
    gpg --dearmor -o /usr/share/keyrings/google-linux-signing.gpg && \
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-linux-signing.gpg] \
    http://dl.google.com/linux/chrome/deb/ stable main" \
    > /etc/apt/sources.list.d/google-chrome.list

### 2) Main install stack
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        google-chrome-stable xvfb openbox  \
        libnss3 libxss1 libatk-bridge2.0-0 libgtk-3-0 \
        libgbm1 libasound2 libunwind8 libdbus-1-3 \
        ffmpeg python3 fonts-dejavu-core fonts-liberation && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY html        ./html
COPY start.sh    ./start.sh
RUN chmod +x ./start.sh
ENTRYPOINT ["./start.sh"]
