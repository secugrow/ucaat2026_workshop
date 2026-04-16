#!/bin/bash

# Set TERM for Docker environment
export TERM=${TERM:-xterm}

# Colors with tput fallback (same pattern as setup_environment.sh)
if command -v tput >/dev/null 2>&1 && tput setaf 1 >/dev/null 2>&1; then
    RED=$(tput setaf 1)
    GREEN=$(tput setaf 2)
    YELLOW=$(tput setaf 3)
    BLUE=$(tput setaf 4)
    CYAN=$(tput setaf 6)
    RESET=$(tput sgr0)
else
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    RESET='\033[0m'
fi

ok()      { printf "%s✔ %s%s\n" "$GREEN" "$*" "$RESET"; }
warn()    { printf "%s⚠ %s%s\n" "$YELLOW" "$*" "$RESET"; }
error()   { printf "%s✖ %s%s\n" "$RED" "$*" "$RESET"; }
info()    { printf "%sℹ %s%s\n" "$BLUE" "$*" "$RESET"; }
section() { printf "\n%s%s%s\n" "$CYAN" "$*" "$RESET"; }

# Load environment — source in the correct order so each layer can depend on the previous.
if [ -f "$HOME/.bashrc" ]; then
    source "$HOME/.bashrc"
else
    warn ".bashrc not found — Android SDK paths may be missing from PATH"
fi

if [ -s "$HOME/.nvm/nvm.sh" ]; then
    export NVM_DIR="$HOME/.nvm"
    source "$NVM_DIR/nvm.sh"
else
    warn "nvm.sh not found — Node.js/Appium may not be on PATH"
fi

if [ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]; then
    export SDKMAN_DIR="$HOME/.sdkman"
    source "$SDKMAN_DIR/bin/sdkman-init.sh"
else
    warn "sdkman-init.sh not found — Java/Maven may not be on PATH"
fi

# Verify appium is available
if ! command -v appium >/dev/null 2>&1; then
    error "Appium not found in PATH"
    info "node:  $(which node  2>/dev/null || echo 'not found')"
    info "npm:   $(which npm   2>/dev/null || echo 'not found')"
    info "PATH:  $PATH"
    exit 1
fi

ok "Appium found: $(appium --version)"

# Check UIAutomator2 driver
section "Checking installed Appium drivers..."
DRIVER_LIST=$(appium driver list --installed 2>&1)

if echo "$DRIVER_LIST" | grep -qi "uiautomator2"; then
    ok "UIAutomator2 driver is installed"
else
    warn "UIAutomator2 driver not found. Server will start but Android automation may not work."
    info "Driver list output: $DRIVER_LIST"
fi

# Chromedriver setup — detect Chrome version on connected devices and download
# matching Chromedriver if not already present.
# Must match chromedriver-executable-dir in appium/.appiumrc.json
CHROMEDRIVER_DIR="$HOME/secugrow/chromedrivers"
mkdir -p "$CHROMEDRIVER_DIR"
declare -A DEVICE_MAJOR

section "Checking Chromedriver..."
# Wait for adb daemon to initialize and enumerate devices.
# Poll until at least one device appears or timeout is reached.
adb start-server >/dev/null 2>&1
DEVICES=""
ADB_TIMEOUT=30
ADB_ELAPSED=0
ADB_INTERVAL=3
while [ -z "$DEVICES" ] && [ "$ADB_ELAPSED" -lt "$ADB_TIMEOUT" ]; do
    DEVICES=$(adb devices | grep -w device | awk '{print $1}')
    if [ -z "$DEVICES" ]; then
        info "Waiting for devices... (${ADB_ELAPSED}s / ${ADB_TIMEOUT}s)"
        sleep "$ADB_INTERVAL"
        ADB_ELAPSED=$((ADB_ELAPSED + ADB_INTERVAL))
    fi
done

if [ -z "$DEVICES" ]; then
    warn "No devices connected after ${ADB_TIMEOUT}s — skipping Chromedriver setup"
else
    for SERIAL in $DEVICES; do
        CHROME_VERSION=""
        for PKG in com.android.chrome com.chrome.beta com.chrome.dev com.chrome.canary; do
            CHROME_VERSION=$(adb -s "$SERIAL" shell dumpsys package "$PKG" 2>/dev/null \
                | grep versionName | head -1 | awk -F= '{print $2}' | tr -d '[:space:]')
            if [ -n "$CHROME_VERSION" ]; then
                info "Detected Chrome from package $PKG: $CHROME_VERSION"
                break
            fi
        done

        if [ -z "$CHROME_VERSION" ]; then
            warn "Could not detect Chrome version on device $SERIAL (tried stable, beta, dev, canary)"
            continue
        fi

        MAJOR_VERSION=$(echo "$CHROME_VERSION" | cut -d. -f1)
        DEVICE_MAJOR[$SERIAL]=$MAJOR_VERSION
        info "Device $SERIAL has Chrome $CHROME_VERSION (major: $MAJOR_VERSION)"

        # Check if a compatible Chromedriver already exists
        EXISTING=$(ls "$CHROMEDRIVER_DIR"/chromedriver-"$MAJOR_VERSION"* 2>/dev/null | head -1)
        if [ -n "$EXISTING" ]; then
            ok "Chromedriver for Chrome $MAJOR_VERSION already present: $EXISTING"
            continue
        fi

        info "Downloading Chromedriver for Chrome $CHROME_VERSION..."

        # Resolve the exact patch version via Google's plain-text endpoint, then
        # construct the download URL directly — no JSON parsing required.
        LATEST_PATCH=$(curl -sf "https://googlechromelabs.github.io/chrome-for-testing/LATEST_RELEASE_${MAJOR_VERSION}")

        if [ -z "$LATEST_PATCH" ]; then
            warn "No Chromedriver release found for Chrome $MAJOR_VERSION on device $SERIAL"
            warn "Tests on device $SERIAL will likely fail — Chrome version may be too new or too old"
            continue
        fi

        DOWNLOAD_URL="https://storage.googleapis.com/chrome-for-testing-public/${LATEST_PATCH}/linux64/chromedriver-linux64.zip"

        info "Downloading from: $DOWNLOAD_URL"
        TMPZIP="/tmp/chromedriver-${MAJOR_VERSION}.zip"
        if wget -q "$DOWNLOAD_URL" -O "$TMPZIP"; then
            TMPDIR=$(mktemp -d)
            unzip -q "$TMPZIP" -d "$TMPDIR"
            mv "$TMPDIR/chromedriver-linux64/chromedriver" "$CHROMEDRIVER_DIR/chromedriver-${MAJOR_VERSION}"
            chmod +x "$CHROMEDRIVER_DIR/chromedriver-${MAJOR_VERSION}"
            rm -rf "$TMPZIP" "$TMPDIR"
            ok "Chromedriver $CHROME_VERSION installed for device $SERIAL"
        else
            warn "Failed to download Chromedriver for Chrome $CHROME_VERSION on device $SERIAL"
            warn "Tests on device $SERIAL will likely fail — check internet connectivity"
        fi
    done
fi

# Print readiness summary before starting Appium.
# Reuses DEVICE_MAJOR collected during the download loop — no second ADB round-trip.
section "Appium readiness summary"
if [ -n "$DEVICES" ]; then
    for SERIAL in $DEVICES; do
        MAJOR=${DEVICE_MAJOR[$SERIAL]:-}
        if [ -n "$MAJOR" ] && ls "$CHROMEDRIVER_DIR"/chromedriver-"$MAJOR"* >/dev/null 2>&1; then
            ok "Device $SERIAL — Chrome $MAJOR — Chromedriver ready"
        elif [ -n "$MAJOR" ]; then
            warn "Device $SERIAL — Chrome $MAJOR — Chromedriver MISSING — tests will fail"
        else
            warn "Device $SERIAL — Chrome version unknown — Chromedriver status unknown"
        fi
    done
else
    warn "No devices connected — connect a device and restart the container"
fi

# Config file is copied to ~/.appiumrc.json by setup_environment.sh (configure_appium step).
# Appium auto-discovers .appiumrc.json in $HOME via lilconfig — no --config flag needed.
CONFIG_FILE="$HOME/.appiumrc.json"

if [ -f "$CONFIG_FILE" ]; then
    ok "Appium configuration found at $CONFIG_FILE"
    section "Starting Appium server (config auto-loaded from ~/.appiumrc.json)..."
    exec appium --address 0.0.0.0
else
    warn "No Appium configuration file found at $CONFIG_FILE"
    section "Starting Appium server with default parameters..."
    exec appium --allow-cors --allow-insecure='*:adb_shell' --address 0.0.0.0 --port 4723
fi