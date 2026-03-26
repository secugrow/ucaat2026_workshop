#!/bin/bash

# Set TERM for Docker environment
export TERM=${TERM:-xterm}

# Colors with tput fallback
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
# .bashrc first (sets base PATH + Android SDK vars), then NVM (node/npm), then SDKMAN (java/mvn).
# Each source is guarded so a missing file is a warning, not a crash.
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

# Check UIAutomator2 driver — use --installed to only list installed drivers
section "Checking installed Appium drivers..."
DRIVER_LIST=$(appium driver list --installed 2>&1)

if echo "$DRIVER_LIST" | grep -qi "uiautomator2"; then
    ok "UIAutomator2 driver is installed"
else
    warn "UIAutomator2 driver not found. Server will start but Android automation may not work."
    info "Driver list output: $DRIVER_LIST"
fi

# Config file is copied to ~/.appium/ by setup_environment.sh (configure_appium step).
# Appium auto-loads it from there — no need to pass --config explicitly.
# TECH-NOTE:    the old path ($HOME/appium/appium.conf.json) was wrong;
#               setup_environment.sh copies the config to $HOME/.appium/appium.conf.json.
CONFIG_FILE="$HOME/.appium/appium.conf.json"

if [ -f "$CONFIG_FILE" ]; then
    ok "Appium configuration found at $CONFIG_FILE"
    section "Starting Appium server (config auto-loaded from ~/.appium/)..."
    exec appium --address 0.0.0.0
else
    warn "No Appium configuration file found at $CONFIG_FILE"
    section "Starting Appium server with default parameters..."
    exec appium --allow-cors --allow-insecure=adb_shell --address 0.0.0.0 --port 4723
fi