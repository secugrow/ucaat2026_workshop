### Build Image

```shell
# Build locally
docker build -t workshop-env:latest .

# Build on NAS and monitor output
docker --context ubuntu-nas build --progress=plain -t workshop-env:latest . 2>&1 | tee /tmp/docker_build.log

# Build locally and monitor output
docker --context default build --progress=plain -t workshop-env:latest . 2>&1 | tee /tmp/docker_build.log
```

**Build time:** 5-15 minutes (setup runs during build)
**Image size:** ~2-3GB (all tools pre-installed)

### Run Image

The container automatically starts Appium server on port 4723 when launched:

```shell
# Run locally: USB + port + daemon mode
docker run -d --name appium-server --privileged -p 4723:4723 -v /dev/bus/usb:/dev/bus/usb workshop-env:latest

# Run on NAS context
docker --context ubuntu-nas run -d --name appium-server --privileged -p 4723:4723 -v /dev/bus/usb:/dev/bus/usb workshop-env:latest
```

**Startup:** Instant - Appium server starts automatically!

### Verify Appium Server

```shell
# Check if container is running
docker ps

# Check Appium server logs
docker logs appium-server

# Test Appium server endpoint
curl http://localhost:4723/status
```

### Container Management

```shell
# Stop the server
docker stop appium-server

# Restart the server
docker start appium-server

# Remove container (to recreate)
docker rm -f appium-server
```

### Interactive Access (Optional)

If you need to access the container shell for debugging:

```shell
# Execute bash in running container
docker exec -it appium-server bash

# Or run a new container in interactive mode
docker run -it --rm --privileged -p 4723:4723 -v /dev/bus/usb:/dev/bus/usb workshop-env:latest bash
```

## Technical Info

### Script Features

`setup_environment.sh` works on both bare metal Ubuntu and Docker containers:

✅ **Color-coded output** - Uses tput with ANSI fallback for Docker builds  
✅ **Smart terminal detection** - Automatically handles missing TERM variable  
✅ **Package manager support** - Works with apt-get and yum  
✅ **Shell detection** - Configures bash/zsh appropriately  
✅ **Dynamic version detection** - Automatically installs latest Android build-tools  
✅ **User-level installation** - Installs to $HOME (NVM, SDKMAN, Android SDK)  
✅ **Sudo support** - Uses sudo only for system packages  
✅ **Idempotent** - Safe to run multiple times  

### Docker Build

- **Build time:** 5-15 minutes (setup runs during `docker build`)
- **Image size:** ~2-3GB (all tools pre-installed)
- **Container startup:** Instant (no runtime setup)
- **Tools included:** Node.js, Appium, Java 23, Maven, Android SDK

### Bare Metal Installation

Works on any Linux system with a standard package manager. Run as a regular user with sudo privileges:

```bash
./setup_environment.sh
```