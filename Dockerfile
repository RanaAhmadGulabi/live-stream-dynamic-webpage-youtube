FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive

# 1) Mark the official Ubuntu repos as “trusted” so apt-get update can succeed
RUN sed -i \
      -e 's|^deb http://archive.ubuntu.com/ubuntu|deb [trusted=yes] http://archive.ubuntu.com/ubuntu|' \
      -e 's|^deb http://security.ubuntu.com/ubuntu|deb [trusted=yes] http://security.ubuntu.com/ubuntu|' \
      /etc/apt/sources.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates apt-transport-https gnupg \
 && rm -rf /var/lib/apt/lists/*

# 2) Switch to HTTPS for Ubuntu and install the rest
RUN sed -i \
      -e 's|http://archive.ubuntu.com/ubuntu|https://archive.ubuntu.com/ubuntu|g' \
      -e 's|http://security.ubuntu.com/ubuntu|https://security.ubuntu.com/ubuntu|g' \
      /etc/apt/sources.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
      wget curl fontconfig xvfb dbus-user-session dbus-x11 \
      libxss1 libappindicator3-1 libindicator7 libnss3 \
      libatk-bridge2.0-0 libgtk-3-0 \
      ffmpeg python3 upower \
      libgl1-mesa-dri libgl1-mesa-glx libgbm1 \
 && wget -qO - https://dl.google.com/linux/linux_signing_key.pub | apt-key add - \
 && echo "deb [arch=amd64] https://dl.google.com/linux/chrome/deb/ stable main" \
       > /etc/apt/sources.list.d/google-chrome.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends google-chrome-stable \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY html/ html/
COPY start.sh ./
RUN chmod +x start.sh

CMD ["./start.sh"]