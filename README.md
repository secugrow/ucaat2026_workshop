## Setup

### Docker (recommended)

```shell
# Build (5-15 min, ~2-3GB image)
docker build -t workshop-env:latest .

# Build with visible output
docker build --progress=plain -t workshop-env:latest . 2>&1 | tee /tmp/docker_build.log

# Run (Appium starts automatically on port 4723)
docker run -d --name appium-server --privileged -p 4723:4723 -v /dev/bus/usb:/dev/bus/usb workshop-env:latest

# Verify
curl http://localhost:4723/status
```

### Bare Metal (Ubuntu)

```shell
chmod u+x setup_environment.sh && ./setup_environment.sh
source ~/.bashrc
```

Tools are installed to `$HOME` (NVM, SDKMAN, Android SDK). Requires sudo for system packages.

---

## Container Management

```shell
docker ps                       # check status
docker logs appium-server       # Appium logs
docker stop appium-server       # stop
docker start appium-server      # restart
docker rm -f appium-server      # remove

# Shell access
docker exec -it appium-server bash
```

## Android Device

USB debugging must be enabled on the device (`Settings → Developer Options → USB Debugging`).
The device must appear in `lsusb` on the host before adb can see it.

```shell
# verify device is recognized
docker exec appium-server adb devices
```

If the device is not listed, replug the USB cable and ensure it is set to **File Transfer (MTP)** mode.

---

## Tools Installed

| Tool | Version |
|---|---|
| Node.js | LTS (via NVM) |
| Appium | latest |
| UIAutomator2 driver | latest |
| Java | 23.0.2 (Liberica) |
| Maven | 3.9.5 |
| Android SDK | latest cmdline-tools, platform-tools, android-33 |
| Chromedriver | auto-downloaded at container startup based on device Chrome version |