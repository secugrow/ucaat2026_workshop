# Workshop Environment Setup Documentation

## Overview

This documentation covers the complete setup environment for the mobile testing workshop, including:
- Automated environment setup script (`setup_environment.sh`)
- Docker containerized environment (`Dockerfile`)
- Appium server startup script (`start-appium.sh`)
- Appium configuration (`.appiumrc.json`)

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Setup Script](#setup-script)
3. [Docker Configuration](#docker-configuration)
4. [Appium Configuration](#appium-configuration)
5. [Appium Startup Script](#appium-startup-script)
6. [Build Instructions](#build-instructions)
7. [Troubleshooting](#troubleshooting)

---

## Architecture Overview

### Core Components

| Component | Version | Purpose |
|-----------|---------|---------|
| Ubuntu | 22.04 | Base OS |
| Node.js | Latest LTS (via NVM) | JavaScript runtime for Appium |
| NVM | 0.39.5 | Node Version Manager |
| Appium | Latest | Mobile automation framework |
| UIAutomator2 | Latest | Android automation driver |
| Java | 23.0.2 (Liberica) | Required for Android SDK tools |
| Maven | 3.9.5 | Build automation |
| Android SDK | Latest | Android development tools |
| SDKMAN | Latest | Java/Maven version manager |
| Chromedriver | Auto-detected | Downloaded at container startup based on device Chrome version |

### Directory Structure

```
ucaat2026_workshop/
├── setup_environment.sh       # Unified installation script (bare metal + Docker build)
├── Dockerfile                 # Docker container definition
├── SETUP_DOCUMENTATION.md     # This file
├── README.md                  # Quick start guide
└── appium/
    ├── start-appium.sh        # Container entry point — starts Appium server
    └── .appiumrc.json         # Appium server configuration (auto-discovered by Appium)
```

---

## Setup Script

### Purpose

`setup_environment.sh` installs the complete workshop environment. It runs:
- **Inside Docker** — automatically during `docker build`
- **On bare metal Ubuntu** — manually by the user

### Key Design Decisions

**Idempotent** — safe to run multiple times. Each installation step checks whether the tool is already present before installing.

**`set -u` compatibility** — NVM and SDKMAN internally use unbound variables. All calls to these tools are wrapped with `set +u` / `set -u` to prevent crashes under strict bash mode.

**Shell detection** — uses `$SHELL` environment variable (reliable in Docker) rather than `ps` process inspection (which fails in minimal container environments).

**Android SDK path** — installs to `$HOME/android_sdk` (absolute, not CWD-relative) so the script works regardless of where it is called from.

### Installation Flow

```
Prerequisites → NVM → Node.js → Appium → Configure Appium →
SDKMAN → Java 23 → Maven 3.9.5 → Android SDK → SDK Components
```

### Appium Configuration Step

`configure_appium()` searches for `.appiumrc.json` in:
1. The script's own directory
2. The `appium/` subdirectory (Docker layout)

It copies the found file to `$HOME/.appiumrc.json`, where Appium auto-discovers it via lilconfig at startup — no `--config` flag needed.

### Chromedriver Setup (Bare Metal)

Chromedriver is handled automatically by Appium on first session. The `.appiumrc.json` config placed in `$HOME` by `setup_environment.sh` enables `relaxed-security` and `uiautomator2:chromedriver_autodownload`, so when the first test session starts Appium detects the Chrome version on the connected device and downloads the matching Chromedriver automatically.

In Docker, `start-appium.sh` pre-downloads the Chromedriver at container startup (before any session is created) so it is ready immediately when tests run.

---

## Docker Configuration

### Dockerfile Overview

```dockerfile
FROM ubuntu:22.04
```

**System packages installed:**

```dockerfile
RUN apt-get update && apt-get install -y \
    curl wget unzip zip sudo bash ca-certificates git \
    libglib2.0-0 libnspr4 libnss3 libdbus-1-3
```

The last four libraries (`libglib2.0-0`, `libnspr4`, `libnss3`, `libdbus-1-3`) are runtime dependencies of Chromedriver. Without them, Chromedriver silently fails to execute.

**User:**

```dockerfile
RUN useradd -m -s /bin/bash appiumuser
```

All tools install to `appiumuser`'s home directory. The container runs as this user.

**Build-time setup:**

```dockerfile
RUN ./setup_environment.sh
```

All tools are baked into the image at build time — container startup is instant.

**PATH for non-login shells:**

```dockerfile
ENV PATH=/home/appiumuser/.nvm/current-bin:/home/appiumuser/android_sdk/platform-tools:...
```

A stable symlink (`current-bin`) points to the NVM-managed Node.js bin directory, avoiding hardcoded version strings. This ensures `docker exec` commands (which don't source `.bashrc`) can find `node`, `appium`, and `adb`.

---

## Appium Configuration

### `.appiumrc.json`

Appium uses [lilconfig](https://github.com/antonk52/lilconfig) to auto-discover its config file. The supported filenames are `.appiumrc`, `.appiumrc.json`, `.appiumrc.yaml` etc. — **not** `appium.conf.json`. The config must be placed in `$HOME` or the working directory.

```json
{
  "server": {
    "port": 4723,
    "allow-cors": true,
    "relaxed-security": true,
    "allow-insecure": ["uiautomator2:chromedriver_autodownload", "uiautomator2:adb_shell"],
    "driver": {
      "uiautomator2": {
        "chromedriver-executable-dir": "/home/appiumuser/secugrow/chromedrivers",
        "chromedriverStorageDir": "/home/appiumuser/secugrow/chromedrivers"
      }
    }
  }
}
```

### Configuration Explained

| Setting | Value | Purpose |
|---------|-------|---------|
| `port` | 4723 | Default Appium port |
| `allow-cors` | true | Enables CORS for web-based clients |
| `relaxed-security` | true | Required for insecure features to work |
| `allow-insecure` | see below | Explicitly enabled insecure features |

**`allow-insecure` format:** Appium 3.x requires the format `automationName:featureName`. Plain feature names without the prefix (e.g. `chromedriver_autodownload`) are silently ignored.

| Feature | Purpose |
|---------|---------|
| `uiautomator2:chromedriver_autodownload` | Allows Appium to auto-download Chromedriver |
| `uiautomator2:adb_shell` | Allows adb shell commands through Appium |

**Note:** The `chromedriver-executable-dir` and `chromedriverStorageDir` settings point to a custom directory, but Chromedriver is actually downloaded by `start-appium.sh` directly into Appium's internal directory where it reliably finds it.

⚠️ `relaxed-security` and `allow-insecure` are for testing/workshop use only.

---

## Appium Startup Script

### Purpose

`start-appium.sh` is the container entry point (`CMD`). It runs every time the container starts and handles:

1. Environment loading (`.bashrc`, NVM, SDKMAN)
2. Appium and UIAutomator2 driver validation
3. **Chromedriver auto-download** based on connected device Chrome version
4. Appium server startup

### Chromedriver Auto-Download

Since the Chrome version on a connected device is not known at image build time, Chromedriver is downloaded at container startup:

```
container starts
    → adb start-server + sleep 3 (wait for device enumeration)
    → detect Chrome version per connected device
    → check if matching Chromedriver already present
    → if not: query Google's known-good-versions API
    → download and install into Appium's internal chromedriver directory
    → start Appium server
```

The download uses `grep`/`awk` only — no Python required. It matches on the major Chrome version and takes the latest available patch.

The Chromedriver persists in the container between restarts. On subsequent starts, the existing binary is reused unless the Chrome version changed.

### Config Discovery

The script checks for `$HOME/.appiumrc.json` (placed there by `setup_environment.sh` during build). If found, Appium is started with `exec appium --address 0.0.0.0` and auto-loads the config. If not found, Appium starts with hardcoded fallback parameters.

---

## Build Instructions

### Prerequisites

- Docker installed and running
- ~4GB free disk space
- Internet connection

### Build

```shell
docker build -t workshop-env:latest .

# With visible output
docker build --progress=plain -t workshop-env:latest . 2>&1 | tee /tmp/docker_build.log
```

Build time: 5-15 minutes. All tools are installed during build — container startup is instant.

### Run

```shell
docker run -d --name appium-server --privileged \
  -p 4723:4723 \
  -v /dev/bus/usb:/dev/bus/usb \
  workshop-env:latest
```

### Verify

```shell
# Appium server status
curl http://localhost:4723/status

# Check adb sees connected device
docker exec appium-server adb devices

# View startup logs
docker logs appium-server
```

---

## Troubleshooting

### Device not seen by adb

```shell
# Check host sees device first
lsusb

# Replug cable, set to File Transfer (MTP) mode
# Confirm USB debugging is enabled on device

docker exec appium-server adb devices
```

### Chromedriver not found

The container downloads Chromedriver at startup. If download fails:

```shell
# Check startup logs
docker logs appium-server | grep -i chromedriver

# Manually verify the download URL for your Chrome version
docker exec appium-server bash -c '
curl -s "https://googlechromelabs.github.io/chrome-for-testing/known-good-versions-with-downloads.json" \
  | grep -o "https://.*146.*linux64/chromedriver[^\"]*" | tail -1'
```

If the container has no internet access, Chromedriver cannot be downloaded automatically.

### Appium config not loaded

Verify the config is in place and valid:

```shell
docker exec appium-server cat /home/appiumuser/.appiumrc.json

# Check Appium startup logs for config confirmation
docker logs appium-server | grep -i "config\|relaxed\|insecure"
```

The log should show:
```
[Appium] Enabling relaxed security...
```

If it doesn't, the config file is either missing, not named `.appiumrc.json`, or contains invalid JSON.

### Docker build fails

```shell
# Check disk space
docker system df

# Clean up and rebuild
docker system prune -a
docker build --no-cache -t workshop-env:latest .
```

---

## Appendix

### File Locations (inside container)

| Component | Location |
|-----------|----------|
| Node.js | `~/.nvm/versions/node/<version>/` |
| Appium | `~/.nvm/versions/node/<version>/lib/node_modules/appium` |
| Java | `~/.sdkman/candidates/java/` |
| Maven | `~/.sdkman/candidates/maven/` |
| Android SDK | `~/android_sdk/` |
| Appium config | `~/.appiumrc.json` |
| Chromedriver | `~/.appium/node_modules/appium-uiautomator2-driver/node_modules/appium-chromedriver/chromedriver/linux/` |
| Chromedriver cache | `~/secugrow/chromedrivers/` |

### Useful Commands

```shell
# Docker
docker ps                          # running containers
docker logs appium-server          # Appium logs
docker exec -it appium-server bash # shell access
docker restart appium-server       # restart

# Appium
docker exec appium-server appium --version
docker exec appium-server appium driver list --installed

# Android
docker exec appium-server adb devices
docker exec appium-server adb -s <serial> shell dumpsys package com.android.chrome | grep versionName
```

---
