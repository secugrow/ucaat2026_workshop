#!/bin/bash

# Author:       chris
# Reason:       Set up complete environment for workshop
# Usage:        chmod u+x setup_environment.sh && ./setup_environment.sh
# Description:  This script installs all necessary tools including Node.js, Appium, Java, Maven, and Android SDK

# Exit on error, treat unset variables as error, and catch pipe failures
set -euo pipefail

# Set default TERM if not set (for Docker builds)
export TERM=${TERM:-xterm}

# Colors via tput (with fallback for environments without tput)
if command -v tput >/dev/null 2>&1 && tput setaf 1 >/dev/null 2>&1; then
    RED=$(tput setaf 1)
    GREEN=$(tput setaf 2)
    YELLOW=$(tput setaf 3)
    BLUE=$(tput setaf 4)
    BOLD=$(tput bold)
    RESET=$(tput sgr0)
else
    # Fallback to ANSI escape codes if tput doesn't work
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    BOLD='\033[1m'
    RESET='\033[0m'
fi

# Helper functions using printf
ok()    { printf "${GREEN}✔ %s${RESET}\n" "$*"; }
warn()  { printf "${YELLOW}⚠ %s${RESET}\n" "$*"; }
error() { printf "${RED}✖ %s${RESET}\n" "$*"; }
info()  { printf "${BLUE}ℹ %s${RESET}\n" "$*"; }

# Multiline output function for heredocs
print_multiline() {
    printf "${BLUE}"
    while IFS= read -r line; do
        printf "%s\n" "$line"
    done
    printf "${RESET}"
}

# Detect shell configuration file
detect_shell_config() {
    # In non-interactive environments (e.g. Docker RUN), ps-based shell detection
    # fails because there is no parent terminal process. Use $SHELL if set,
    # otherwise fall back to .bashrc which is always safe on Linux.
    local detected_shell
    if [[ -n "${SHELL:-}" ]]; then
        detected_shell=$(basename "$SHELL")
    else
        # Try ps only if we have a real TTY; ignore errors silently
        detected_shell=$(ps -p "$(ps -o ppid= -p $$ 2>/dev/null | tr -d ' ')" -o comm= 2>/dev/null | sed 's/^-//' || echo "bash")
    fi

    case "$detected_shell" in
        zsh)
            SHELL_CONFIG_FILE="$HOME/.zshrc"
            ;;
        bash)
            if [[ "$OSTYPE" == "linux-gnu"* ]]; then
                if [[ -f "$HOME/.bashrc" ]]; then
                    SHELL_CONFIG_FILE="$HOME/.bashrc"
                else
                    SHELL_CONFIG_FILE="$HOME/.profile"
                fi
            else
                SHELL_CONFIG_FILE="$HOME/.bashrc"
            fi
            ;;
        *)
            SHELL_CONFIG_FILE="$HOME/.bashrc"
            ;;
    esac
}

# Install basic prerequisites
install_prerequisites() {
    info "Checking prerequisites..."

    # Check if curl is installed
    if ! command -v curl >/dev/null 2>&1; then
        warn "curl could not be found, installing..."
        if [[ "$OSTYPE" == "linux-gnu"* ]]; then
            if command -v apt-get >/dev/null 2>&1; then
                sudo apt-get update
                sudo apt-get install -y curl
            elif command -v yum >/dev/null 2>&1; then
                sudo yum install -y curl
            else
                error "Unsupported package manager. Please install curl manually."
                exit 1
            fi
        else
            error "Unsupported OS. Please install curl manually."
            exit 1
        fi
    fi

    # Check if wget is installed
    if ! command -v wget >/dev/null 2>&1; then
        error "wget is not installed. Please install wget manually and rerun the script."
        exit 1
    fi

    # Check if unzip is installed
    if ! command -v unzip >/dev/null 2>&1; then
        warn "unzip could not be found, installing..."
        if [[ "$OSTYPE" == "linux-gnu"* ]]; then
            sudo apt-get update
            sudo apt-get install -y unzip
        else
            error "Unable to install unzip. Please install it manually."
            exit 1
        fi
    fi

    ok "Prerequisites confirmed"
}

# Install NVM (Node Version Manager)
install_nvm() {
    if [ -d "$HOME/.nvm" ]; then
        ok "NVM is already installed"
        # Load NVM in the current shell session
        export NVM_DIR="$HOME/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
        [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
    else
        info "Installing NVM..."
        NVM_INSTALL_URL="https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.5/install.sh"
        if command -v curl >/dev/null 2>&1; then
            curl -o- "$NVM_INSTALL_URL" | bash
        elif command -v wget >/dev/null 2>&1; then
            wget -qO- "$NVM_INSTALL_URL" | bash
        else
            error "curl or wget is required to download NVM."
            exit 1
        fi
        # Load NVM in the current shell session
        export NVM_DIR="$HOME/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
        [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
        ok "NVM installed successfully"
    fi
}

# Install Node.js and npm
install_node_and_npm() {
    # Ensure NVM is available as a shell function (it is sourced, not a binary)
    if ! type nvm >/dev/null 2>&1; then
        error "NVM is not loaded. Please check the installation."
        exit 1
    fi

    # NVM internal code uses unbound variables which trips set -u.
    # Suspend nounset around all nvm calls.
    set +u

    if command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
        ok "Node.js already installed: $(node -v)"
        ok "npm already installed: $(npm -v)"
        nvm use --lts >/dev/null 2>&1 || true
    else
        info "Installing Node.js LTS via NVM..."
        nvm install --lts
        nvm use --lts
        nvm alias default 'lts/*'
        set -u
        if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1; then
            error "Node.js or npm was not installed properly."
            exit 1
        fi
        info "Node.js version: $(node -v)"
        info "npm version: $(npm -v)"
        ok "Node.js and npm installed successfully"
        set +u
    fi

    set -u
}

# Install the latest version of Appium
install_appium() {
    if command -v appium >/dev/null 2>&1; then
        ok "Appium already installed: $(appium --version)"
    else
        info "Installing the latest version of Appium..."
        if ! command -v npm >/dev/null 2>&1; then
            error "npm is not installed. Appium installation failed."
            exit 1
        fi
        npm install -g appium

        if ! command -v appium >/dev/null 2>&1; then
            error "Appium was not installed properly."
            exit 1
        fi
        ok "Appium installed successfully. Version: $(appium --version)"
    fi

    # Install UIAutomator2 driver (idempotent check)
    if appium driver list --installed 2>/dev/null | grep -q "uiautomator2"; then
        ok "UIAutomator2 driver already installed"
    else
        info "Installing UIAutomator2 driver..."
        if appium driver install uiautomator2; then
            ok "UIAutomator2 driver installed successfully"
        else
            error "Failed to install UIAutomator2 driver"
            exit 1
        fi
    fi
}

# Configure Appium
configure_appium() {
    info "Configuring Appium..."

    APPIUM_CONFIG_DIR="$HOME/.appium"
    mkdir -p "$APPIUM_CONFIG_DIR"

    # Look for appium.conf.json in the script directory and the appium/ subdirectory
    # In Docker the layout is: setup_environment.sh and appium/ are siblings under WORKDIR
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [ -f "$SCRIPT_DIR/appium.conf.json" ]; then
        APPIUM_CONF_SRC="$SCRIPT_DIR/appium.conf.json"
    elif [ -f "$SCRIPT_DIR/appium/appium.conf.json" ]; then
        APPIUM_CONF_SRC="$SCRIPT_DIR/appium/appium.conf.json"
    else
        APPIUM_CONF_SRC=""
    fi

    if [ -n "$APPIUM_CONF_SRC" ]; then
        info "Copying $APPIUM_CONF_SRC to $APPIUM_CONFIG_DIR"
        # cp "$APPIUM_CONF_SRC" "$APPIUM_CONFIG_DIR/appium.conf.json"
        cp "$APPIUM_CONF_SRC" "$HOME/.appiumrc.json"

        CHROMEDRIVER_DIR="$HOME/secugrow/chromedrivers"
        mkdir -p "$CHROMEDRIVER_DIR"
        ok "Created chromedriver storage directory at $CHROMEDRIVER_DIR"
    else
        warn "No appium.conf.json found in $SCRIPT_DIR or $SCRIPT_DIR/appium/. Skipping Appium configuration."
    fi
}

# Install SDKMAN
install_sdkman() {
    # SDKMAN's init script uses unbound variables internally — suspend nounset around all sdk calls
    set +u

    if [ -d "$HOME/.sdkman" ]; then
        ok "SDKMAN is already installed. Skipping installation..."
        export SDKMAN_DIR="$HOME/.sdkman"
        [ -s "$SDKMAN_DIR/bin/sdkman-init.sh" ] && \. "$SDKMAN_DIR/bin/sdkman-init.sh"
    else
        if command -v zip >/dev/null 2>&1 && command -v unzip >/dev/null 2>&1; then
            ok "zip and unzip are already installed"
        else
            info "Installing zip, unzip, and dependencies for SDKMAN..."
            if command -v apt-get >/dev/null 2>&1; then
               sudo apt-get update && sudo apt-get install -y zip unzip
            elif command -v yum >/dev/null 2>&1; then
               sudo yum install -y zip unzip
            else
               error "Unsupported package manager. Please install zip and unzip manually."
               set -u
               exit 1
            fi
        fi

        info "Installing SDKMAN..."
        SDKMAN_INSTALL_URL="https://get.sdkman.io"
        if command -v curl >/dev/null 2>&1; then
            curl -s "$SDKMAN_INSTALL_URL" | bash
        elif command -v wget >/dev/null 2>&1; then
            wget -qO- "$SDKMAN_INSTALL_URL" | bash
        else
            error "curl or wget is required to download SDKMAN."
            set -u
            exit 1
        fi

        export SDKMAN_DIR="$HOME/.sdkman"
        [ -s "$SDKMAN_DIR/bin/sdkman-init.sh" ] && \. "$SDKMAN_DIR/bin/sdkman-init.sh"

        if ! command -v sdk >/dev/null 2>&1; then
            error "SDKMAN was not installed properly."
            set -u
            exit 1
        fi
        ok "SDKMAN installed successfully"
    fi

    set -u
}

# Install Maven and Java using SDKMAN
install_maven_and_java() {
    info "Ensuring SDKMAN is loaded..."

    # SDKMAN's init script and sdk commands use unbound variables — suspend nounset throughout
    set +u
    [ -s "$HOME/.sdkman/bin/sdkman-init.sh" ] && . "$HOME/.sdkman/bin/sdkman-init.sh"

    # Check specifically for Java 23 (not just any java)
    if java -version 2>&1 | grep -q "version \"23"; then
        ok "Java 23 already installed: $(java -version 2>&1 | head -n 1)"
    else
        if command -v java >/dev/null 2>&1; then
            warn "A different Java version is installed ($(java -version 2>&1 | head -n 1)). Installing Java 23 via SDKMAN..."
        else
            info "Installing Java 23 via SDKMAN..."
        fi

        sdk install java 23.0.2-librca || true
        sdk default java 23.0.2-librca

        # Reload so java points to new default
        [ -s "$HOME/.sdkman/bin/sdkman-init.sh" ] && . "$HOME/.sdkman/bin/sdkman-init.sh"
    fi

    set -u
    detect_shell_config
    info "Using shell configuration file: $SHELL_CONFIG_FILE"
    set +u

    if ! java -version 2>&1 | grep -q "version \"23"; then
        error "Java 23 was not installed or set properly. Try sourcing $SHELL_CONFIG_FILE and re-running."
        set -u
        exit 1
    fi

    ok "Java installed successfully: $(java -version 2>&1 | head -n 1)"

    if command -v mvn >/dev/null 2>&1; then
        ok "Maven already installed: $(mvn -v 2>/dev/null | head -n 1)"
    else
        info "Installing Maven 3.9.5 via SDKMAN..."
        sdk install maven 3.9.5 || true
        sdk default maven 3.9.5
        [ -s "$HOME/.sdkman/bin/sdkman-init.sh" ] && . "$HOME/.sdkman/bin/sdkman-init.sh"
    fi

    if ! command -v mvn >/dev/null 2>&1; then
        error "Maven was not installed properly."
        exit 1
    fi

    ok "Maven installed. Version: $(mvn -v | head -n 1)"
}

# Download and extract Android SDK
download_and_extract_sdk() {
    info "Downloading Android SDK..."

    # Use a stable absolute path instead of $(pwd) to make the script location-independent
    ANDROID_SDK_ROOT_DIR="$HOME/android_sdk"

    # Idempotent: skip download if SDK directory already exists
    if [[ -d "$ANDROID_SDK_ROOT_DIR/cmdline-tools/latest" ]]; then
        ok "Android SDK command-line tools already present at $ANDROID_SDK_ROOT_DIR. Skipping download."
        return 0
    fi

    # Fetch the latest version from Android's repository XML
    info "Fetching latest commandlinetools version..."
    REPO_XML=$(wget -qO- https://dl.google.com/android/repository/repository2-3.xml)
    LATEST_VERSION=$(echo "$REPO_XML" | grep -oE 'commandlinetools-linux-[0-9]+_latest\.zip' | head -1)

    if [[ -z "$LATEST_VERSION" ]]; then
        error "Failed to fetch latest version. Falling back to known version."
        LATEST_VERSION="commandlinetools-linux-11076708_latest.zip"
    fi

    info "Using version: $LATEST_VERSION"
    URL="https://dl.google.com/android/repository/$LATEST_VERSION"
    OUTPUT="/tmp/$LATEST_VERSION"

    info "Downloading Android SDK (~160MB, please wait)..."
    if wget --progress=dot:mega -O "$OUTPUT" "$URL" 2>&1 | grep --line-buffered -E "[0-9]+%" | sed -u 's/.* \([0-9]\+%\).*/  [\1]/' | grep -E "(25%|50%|75%|100%)"; then
        ok "Download complete"
    else
        error "Download failed"
        exit 1
    fi

    info "Unzipping downloaded package..."
    mkdir -p "$ANDROID_SDK_ROOT_DIR/cmdline-tools"
    unzip -q "$OUTPUT" -d "$ANDROID_SDK_ROOT_DIR/cmdline-tools"
    # Restructure to proper SDK layout: cmdline-tools/latest/
    mv "$ANDROID_SDK_ROOT_DIR/cmdline-tools/cmdline-tools" "$ANDROID_SDK_ROOT_DIR/cmdline-tools/latest"
    rm "$OUTPUT" # Clean up the downloaded ZIP file after unzipping
}

# Configure environment variables
configure_android_environment() {
    info "Configuring Android environment variables..."

    # ANDROID_SDK_ROOT_DIR must match the value set in download_and_extract_sdk
    ANDROID_SDK_ROOT_DIR="$HOME/android_sdk"

    detect_shell_config
    info "Using shell configuration file: $SHELL_CONFIG_FILE"

    if grep -q "ANDROID_SDK_ROOT=" "$SHELL_CONFIG_FILE"; then
        warn "ANDROID_SDK_ROOT is already configured in $SHELL_CONFIG_FILE. Skipping addition."
    else
        info "Adding ANDROID_SDK_ROOT and PATH modifications to $SHELL_CONFIG_FILE"

        # Expand all paths at write time so the shell config is self-contained
        # and does not depend on variables being defined in a particular order
        local CMDLINE_TOOLS_PATH="$ANDROID_SDK_ROOT_DIR/cmdline-tools/latest/bin"
        local PLATFORM_TOOLS_PATH="$ANDROID_SDK_ROOT_DIR/platform-tools"
        local BUILD_TOOLS_PATH="$ANDROID_SDK_ROOT_DIR/build-tools"

        # Find the line number of the last occurrence of 'export PATH='
        last_path_line=$(awk '/export PATH=/ { last_match=NR } END { print last_match }' "$SHELL_CONFIG_FILE")

        # If no 'export PATH=' is found, find the first occurrence of SDKMAN installation
        if [[ -z "$last_path_line" ]]; then
            sdkman_line=$(awk '/sdkman-init.sh/ { print NR; exit }' "$SHELL_CONFIG_FILE")
            if [[ -z "$sdkman_line" ]]; then
                # If no SDKMAN installation is found, append to the end of the file
                sdkman_line=$(wc -l < "$SHELL_CONFIG_FILE")
            fi
            last_path_line=$((sdkman_line - 3))
        fi

        # Insert environment variables above the determined line
        # All paths are fully expanded — no chained variable references
        awk -v insert_line="$last_path_line" \
            -v current_date="$(date '+%Y-%m-%d %H:%M:%S')" \
            -v sdk_root="$ANDROID_SDK_ROOT_DIR" \
            -v cmdline_tools="$CMDLINE_TOOLS_PATH" \
            -v platform_tools="$PLATFORM_TOOLS_PATH" \
            -v build_tools="$BUILD_TOOLS_PATH" '
        { print }
        NR == insert_line {
            print "##### Android SDK Environment Variables (added on " current_date ") #####"
            print "export ANDROID_SDK_ROOT=\"" sdk_root "\""
            print "export ANDROID_CMDLINE_TOOLS=\"" cmdline_tools "\""
            print "export ANDROID_PLATFORM_TOOLS=\"" platform_tools "\""
            print "# Build tools path resolves the installed version at shell startup"
            print "export ANDROID_BUILD_TOOLS=\"$(ls -d " build_tools "/* 2>/dev/null | sort -V | tail -1)\""
            print "export PATH=\"" cmdline_tools ":" platform_tools ":$ANDROID_BUILD_TOOLS:$PATH\""
        }' "$SHELL_CONFIG_FILE" > "$SHELL_CONFIG_FILE.tmp" && mv "$SHELL_CONFIG_FILE.tmp" "$SHELL_CONFIG_FILE"

        ok "ANDROID_SDK_ROOT and PATH modifications added to $SHELL_CONFIG_FILE"
    fi
}

# Install Android SDK components
install_sdk_components() {
    info "Installing Android SDK components..."

    # Must match the path used in download_and_extract_sdk and configure_android_environment
    ANDROID_SDK_ROOT_DIR="$HOME/android_sdk"
    ANDROID_CMDLINE_TOOLS="$ANDROID_SDK_ROOT_DIR/cmdline-tools/latest"

    # Ensure SDKMAN is loaded to access Java
    if [ -d "$HOME/.sdkman" ]; then
        export SDKMAN_DIR="$HOME/.sdkman"
        set +u
        [ -s "$SDKMAN_DIR/bin/sdkman-init.sh" ] && source "$SDKMAN_DIR/bin/sdkman-init.sh"
        set -u
    fi

    # Verify Java is available
    if ! command -v java >/dev/null 2>&1; then
        error "Java is not available. Cannot proceed with SDK installation."
        exit 1
    fi

    # Accept licenses with finite printf instead of infinite yes to avoid SIGPIPE
    info "Accepting Android SDK licenses..."
    printf 'y\n%.0s' {1..100} | "$ANDROID_CMDLINE_TOOLS/bin/sdkmanager" \
        --sdk_root="$ANDROID_SDK_ROOT_DIR" --licenses >/dev/null 2>&1 || true

    LATEST_BUILD_TOOLS=$("$ANDROID_CMDLINE_TOOLS/bin/sdkmanager" --sdk_root="$ANDROID_SDK_ROOT_DIR" --list 2>/dev/null \
        | grep "build-tools;" \
        | awk '{print $1}' \
        | sort -t';' -k2 -V \
        | tail -1)

    if [[ -z "$LATEST_BUILD_TOOLS" ]]; then
        warn "Could not detect latest build-tools, using fallback version 35.0.0"
        LATEST_BUILD_TOOLS="build-tools;35.0.0"
    else
        info "Installing latest build-tools: $LATEST_BUILD_TOOLS"
    fi

    info "Installing platform-tools, platforms;android-33 and $LATEST_BUILD_TOOLS..."
    printf 'y\n%.0s' {1..100} | "$ANDROID_CMDLINE_TOOLS/bin/sdkmanager" \
        --sdk_root="$ANDROID_SDK_ROOT_DIR" \
        --install "platform-tools" "platforms;android-33" "$LATEST_BUILD_TOOLS"

    # Verify adb is actually present after install
    if [ ! -f "$ANDROID_SDK_ROOT_DIR/platform-tools/adb" ]; then
        error "platform-tools install failed — adb not found"
        exit 1
    fi

    # Export build-tools version for later use
    export ANDROID_BUILD_TOOLS_VERSION=$(echo "$LATEST_BUILD_TOOLS" | cut -d';' -f2)

    ok "Android SDK installation completed successfully."
    info "Build tools version: $ANDROID_BUILD_TOOLS_VERSION"
}

# Main script execution
main() {
    info "Starting complete environment setup..."

    install_prerequisites
    install_nvm
    install_node_and_npm
    install_appium
    configure_appium
    install_sdkman
    install_maven_and_java
    download_and_extract_sdk
    configure_android_environment
    install_sdk_components

    ok "All installations completed successfully."

    # Source the shell config to make everything available immediately
    detect_shell_config
    info "Sourcing $SHELL_CONFIG_FILE to activate all installed tools..."
    source "$SHELL_CONFIG_FILE"

    ok "Setup complete! All tools are now available."

    # Display versions of all installed components
    print_multiline <<EOF
$(tput bold)======================================$(tput sgr0)
$(tput bold)    Installed Component Versions      $(tput sgr0)
$(tput bold)======================================$(tput sgr0)

$(tput setaf 6)Node.js:$(tput sgr0)     $(node -v 2>/dev/null || echo "Not available")
$(tput setaf 6)npm:$(tput sgr0)         $(npm -v 2>/dev/null || echo "Not available")
$(tput setaf 6)Appium:$(tput sgr0)      $(appium --version 2>/dev/null || echo "Not available")
$(tput setaf 6)Java:$(tput sgr0)        $(java -version 2>&1 | head -n 1 || echo "Not available")
$(tput setaf 6)Maven:$(tput sgr0)       $(mvn -v 2>/dev/null | head -n 1 | sed 's/Apache Maven //' || echo "Not available")
$(tput setaf 6)Android SDK:$(tput sgr0) $([ -d "$ANDROID_SDK_ROOT_DIR" ] && echo "Installed at $ANDROID_SDK_ROOT_DIR" || echo "Not available")

$(tput bold)======================================$(tput sgr0)
EOF
}

main
exit 0