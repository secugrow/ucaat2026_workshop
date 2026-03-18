#!/bin/bash

# Set TERM for Docker environment
export TERM=${TERM:-xterm}

# Color definitions and helper functions
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
BLUE=$(tput setaf 4)
CYAN=$(tput setaf 6)
MAGENTA=$(tput setaf 5)
RESET=$(tput sgr0)

ok()      { printf "%s✔ %s%s\n" "$GREEN" "$*" "$RESET"; }
warn()    { printf "%s⚠ %s%s\n" "$YELLOW" "$*" "$RESET"; }
error()   { printf "%s✖ %s%s\n" "$RED" "$*" "$RESET"; }
info()    { printf "%sℹ %s%s\n" "$BLUE" "$*" "$RESET"; }
section() { printf "\n%s%s%s\n" "$CYAN" "$*" "$RESET"; }

# Load all environment configurations
source ~/.bashrc
source ~/.nvm/nvm.sh
source ~/.sdkman/bin/sdkman-init.sh

# Verify appium is available
if ! command -v appium &> /dev/null; then
    error "Appium not found in PATH"
    info "Available commands: $(which node npm || echo 'none')"
    info "NODE_PATH: $(which node || echo 'not found')"
    info "PATH: $PATH"
    exit 1
fi

# Display Appium version and driver information
ok "Appium found: $(appium --version)"

# List installed drivers
section "Checking installed Appium drivers..."
DRIVER_LIST=$(appium driver list 2>&1)

# Debug: show the raw output
info "Raw driver list output:"
echo "$DRIVER_LIST"

# Debug: show what grep finds
info "Searching for uiautomator2 lines:"
echo "$DRIVER_LIST" | grep "uiautomator2" || info "No matches found"

# Check if UIAutomator2 is installed
if echo "$DRIVER_LIST" | grep -q "uiautomator2.*\[installed"; then
    ok "UIAutomator2 driver is installed"
else
    error "UIAutomator2 driver is NOT installed"
    warn "UIAutomator2 driver not found. Server will start but Android automation may not work."
fi

# Check if Appium configuration file exists
CONFIG_FILE="$HOME/appium/appium.conf.json"

if [ -f "$CONFIG_FILE" ]; then
    ok "Found Appium configuration file: $CONFIG_FILE"
    section "Configuration contents:"
    cat "$CONFIG_FILE"
    info "--- End of configuration ---"

    # Start Appium server - configuration will be automatically loaded from ~/.appium/
    section "Starting Appium server with configuration file (auto-loaded)..."
    exec appium --address 0.0.0.0
else
    warn "No Appium configuration file found at $CONFIG_FILE"
    section "Starting Appium server with command line parameters..."
    # Fallback to command line parameters
    exec appium --allow-cors --allow-insecure=*:adb_shell --address 0.0.0.0 --port 4723
fi