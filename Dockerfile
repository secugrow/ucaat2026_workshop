FROM ubuntu:22.04

# Set non-interactive frontend to avoid prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Update package list and install essential dependencies
# libglib2.0-0, libnspr4, libnss3, libdbus-1-3 are required by Chromedriver
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    unzip \
    zip \
    sudo \
    bash \
    ca-certificates \
    git \
    libglib2.0-0 \
    libnspr4 \
    libnss3 \
    libdbus-1-3 \
    && rm -rf /var/lib/apt/lists/*

# Create a test user with sudo privileges
RUN useradd -m -s /bin/bash appiumuser && \
    echo "appiumuser ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

# Set working directory
WORKDIR /home/appiumuser

# Copy the installation script, startup script, and Appium config
COPY setup_environment.sh ./

COPY appium/ ./appium/

# Make scripts executable and change ownership
RUN chmod +x setup_environment.sh appium/start-appium.sh && \
    chown appiumuser:appiumuser setup_environment.sh appium/

# Switch to test user
USER appiumuser

# Run the setup script during build time
RUN ./setup_environment.sh

# Print installed component versions so they are visible in docker build output
RUN bash -c '\
    source ~/.bashrc && \
    source ~/.nvm/nvm.sh && \
    export SDKMAN_DIR="$HOME/.sdkman" && \
    source ~/.sdkman/bin/sdkman-init.sh && \
    echo "" && \
    echo "======================================" && \
    echo "    Installed Component Versions      " && \
    echo "======================================" && \
    echo "Node.js:     $(node -v 2>/dev/null || echo Not available)" && \
    echo "npm:         $(npm -v 2>/dev/null || echo Not available)" && \
    echo "Appium:      $(appium --version 2>/dev/null || echo Not available)" && \
    echo "Java:        $(java -version 2>&1 | head -n 1 || echo Not available)" && \
    echo "Maven:       $(mvn -v 2>/dev/null | head -n 1 | sed "s/Apache Maven //" || echo Not available)" && \
    echo "Android SDK: $([ -d /home/appiumuser/android_sdk ] && echo Installed at /home/appiumuser/android_sdk || echo Not available)" && \
    echo "adb:         $(adb version 2>/dev/null | head -n 1 || echo Not available)" && \
    echo "======================================"'

# Create a stable symlink for the NVM-managed Node.js bin directory.
# Finds the actual installed version directory rather than relying on NVM aliases.
RUN ln -s "$(ls -d /home/appiumuser/.nvm/versions/node/*/bin | head -1)" \
         /home/appiumuser/.nvm/current-bin

# Set environment variables so tools are available in all contexts
# (docker exec, CMD, etc.) without needing to source .bashrc
ENV NVM_DIR=/home/appiumuser/.nvm \
    SDKMAN_DIR=/home/appiumuser/.sdkman \
    ANDROID_SDK_ROOT=/home/appiumuser/android_sdk \
    TERM=xterm \
    PATH=/home/appiumuser/.nvm/current-bin:/home/appiumuser/android_sdk/platform-tools:/home/appiumuser/android_sdk/cmdline-tools/latest/bin:$PATH

# start appium
CMD ["./appium/start-appium.sh"]