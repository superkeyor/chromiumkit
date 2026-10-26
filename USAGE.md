# Using chromiumkit as a base image

Base = Debian trixie + Chromium + chromedriver + Xvfb + x11vnc + noVNC.
No Python/Miniforge/tini/cron/tzdata here; the app image gets those from `dockerapp_template`.

## 1. App Dockerfile

Take `dockerapp_template/Dockerfile` unchanged except the first lines:

```dockerfile
FROM superkeyor/chromiumkit:latest
ARG MINIFORGE_VERSION=26.9.4-0
```

(Replaces `FROM debian:trixie-...-slim`. Everything else stays, including its
`ENTRYPOINT ["tini", "--"]`.) Put `selenium` (or `seleniumbase`) in `environment.yml`.

## 2. start.sh

Call `vnc-start` once, before launching the app:

```bash
#!/usr/bin/env bash

if [ "$ENABLE_CRON" = "true" ]; then
    cron
fi

# Starts the ONE Xvfb (:99, -nolisten tcp); plus x11vnc + noVNC if ENABLE_VNC=true.
# DISPLAY=:99 is already set in the image, so the app inherits it. Exits 1 if Xvfb fails.
vnc-start || exit 1

exec python main.py   # exec: app gets SIGTERM directly
```

Cron jobs do NOT inherit the container env. In `crontab`, set it per line or at the top:
`DISPLAY=:99`.

## 3. docker-compose.yml

```yaml
services:
    myapp:
        shm_size: 2gb                    # chromium crashes on the default 64MB /dev/shm
        ports:
            - "127.0.0.1:6080:6080"      # noVNC; keep on localhost (or put behind a proxy)
        environment:
            - ENABLE_VNC=true            # default false: Xvfb only, no VNC/noVNC
            - VNC_PASSWORD=${VNC_PASSWORD}   # empty = no password, anyone reaching 6080 controls the browser
            # - SCREEN_GEOMETRY=1920x1080x24
```

Open `http://localhost:6080/` (noVNC; click Connect, enter the password).
Put `ENABLE_VNC=true` in `docker-compose.override.yml` (dev) and leave it off in production
if you don't need to watch.

## 4. Env vars provided by the base

| Var | Default | Meaning |
|---|---|---|
| `DISPLAY` | `:99` | Display of the single Xvfb. Don't start another one. |
| `ENABLE_VNC` | `false` | `true` = also start x11vnc + noVNC on 6080 |
| `VNC_PASSWORD` | empty | Password for VNC |
| `SCREEN_GEOMETRY` | `1920x1080x24` | Xvfb screen `WxHxDepth` |

## 5. Selenium

Run Chromium headed (do not pass `--headless`) so it shows on the display:

```python
from selenium import webdriver
from selenium.webdriver.chrome.service import Service

opts = webdriver.ChromeOptions()
opts.binary_location = "/usr/bin/chromium"
opts.add_argument("--no-sandbox")              # container runs as root
opts.add_argument("--disable-dev-shm-usage")   # extra safety if shm is small
opts.add_argument("--window-size=1920,1080")
driver = webdriver.Chrome(service=Service("/usr/bin/chromedriver"), options=opts)
```

Chromium and chromedriver both come from Debian, so their versions always match.

SeleniumBase: run headed and never let it start its own display (no `xvfb=True` /
`--xvfb`), so it uses `DISPLAY=:99`. Verify with `pgrep -a Xvfb`: there must be exactly one.

```python
with SB(browser="chrome", headed=True, binary_location="/usr/bin/chromium") as sb: ...
with SB(browser="chrome", uc=True, headed=True, binary_location="/usr/bin/chromium") as sb: ...
```

**arm64 (Apple Silicon / Pi) + SeleniumBase `uc=True`:** SeleniumBase downloads Google's
chromedriver, which is x86-64 only, so `uc` mode dies with
`Service .../uc_driver unexpectedly exited. Status code was: 255`
(`Dynamic loader not found: ld-linux-x86-64`). Fix: point it at the Debian driver. Add to
the app Dockerfile, after the `mamba env create` step:

```dockerfile
RUN D=$(python -c "import seleniumbase,os;print(os.path.dirname(seleniumbase.__file__))")/drivers && \
    ln -sf /usr/bin/chromedriver $D/uc_driver && ln -sf /usr/bin/chromedriver $D/chromedriver
```

Tested on arm64 (OrbStack): both modes work with this and exactly one Xvfb runs. Plain
headed mode also worked without the fix, though SeleniumBase still downloaded the x86
driver; the symlink also avoids that download. On amd64 the download is valid, but
the symlink is still fine.

## 6. Debugging

- `docker exec -it myapp pgrep -a "Xvfb|x11vnc|websockify"`
- `pkill chromium` / `pkill chromedriver` to clear zombie browsers (procps is installed).
- No window manager, so windows have no title bar; use `--window-size`/`--start-maximized`.
