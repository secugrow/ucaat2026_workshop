FROM ubuntu:22.04

# Set non-interactive frontend to avoid prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Update package list and install essential dependencies
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    unzip \
    zip \
    sudo \
    bash \
    ca-certificates \
    git \
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

# Create a stable symlink for the NVM-managed Node.js bin directory so the
# PATH below doesn't need a hardcoded version string (e.g. v24.14.1)
RUN ln -s "$(. ~/.nvm/nvm.sh && nvm which default | xargs dirname)" \
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