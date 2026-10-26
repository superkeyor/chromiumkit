# =============================================================================
# Base Image: Debian trixie + Chromium/chromedriver + Xvfb + noVNC
# =============================================================================
# Only the chromium/VNC pieces live here. Everything else (Miniforge, tini, tzdata,
# cron, TZ, python envs, WORKDIR, ENTRYPOINT) comes from the app image, i.e. from
# dockerapp_template, whose only change is:
#   FROM superkeyor/python_chromium_driver:latest
#   ARG MINIFORGE_VERSION=26.9.4-0
# and (the one addition elsewhere) a `vnc-start` line in the app's start.sh.
#
# https://hub.docker.com/_/debian/tags
# Use fixed versions (vs. latest) to avoid freq rebuild
FROM debian:trixie-20261020-slim

# Virtual display used by (non-headless) chromium; watch it via noVNC
ENV DISPLAY=:99
ENV ENABLE_VNC=false
ENV VNC_PASSWORD=
ENV SCREEN_GEOMETRY=1920x1080x24

# procps: pkill for killing zombie chromium processes
# chromium + chromium-driver: from Debian, so versions always match
# xvfb xauth: virtual display; x11vnc + novnc + websockify: view it in a browser
# fonts-liberation: sane default fonts for rendering pages
RUN export DEBIAN_FRONTEND=noninteractive && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        procps \
        chromium \
        chromium-driver \
        xvfb \
        xauth \
        x11vnc \
        novnc \
        websockify \
        fonts-liberation && \
    ln -sf /usr/share/novnc/vnc.html /usr/share/novnc/index.html && \
    rm -rf /var/lib/apt/lists/*

# Call `vnc-start` from the app's start.sh (it no-ops unless ENABLE_VNC=true)
COPY vnc-start.sh /usr/local/bin/vnc-start
RUN chmod +x /usr/local/bin/vnc-start

# noVNC web UI (VNC itself, 5900, stays inside the container)
EXPOSE 6080
