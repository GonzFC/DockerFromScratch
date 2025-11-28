# DockerFromScratch

Idempotent bash script to set up a complete Docker host with **Portainer CE** and optionally **Nginx Proxy Manager** on Ubuntu Server 24.04 LTS.

## Features

- **Idempotent**: Safe to run multiple times without side effects
- **Interactive**: Prompts for all configuration options
- **Modular**: NPM is optional - install only what you need
- **Complete**: Sets up Docker, Portainer, firewall, and networking
- **Docker 29+ Compatible**: Includes fix for Portainer compatibility with Docker 29+
- **Quick Start Guides**: Provides step-by-step instructions after installation
- **Uninstall Support**: Can remove NPM if no longer needed

## Quick Install

```bash
curl -fsSL https://raw.githubusercontent.com/GonzFC/DockerFromScratch/main/setup.sh | bash
```

Or download and run:

```bash
curl -fsSL https://raw.githubusercontent.com/GonzFC/DockerFromScratch/main/setup.sh -o setup.sh
chmod +x setup.sh
./setup.sh
```

## Command Line Options

```
Usage: setup.sh [OPTIONS]

OPTIONS:
    --help              Show help message
    --uninstall-npm     Uninstall Nginx Proxy Manager

EXAMPLES:
    ./setup.sh                  Run interactive setup
    ./setup.sh --uninstall-npm  Remove NPM container and data
```

## Requirements

- Ubuntu Server 24.04 LTS (fresh or existing install)
- User with sudo privileges (do NOT run as root)
- Internet connectivity

## What Gets Installed

| Component | Purpose | Optional |
|-----------|---------|----------|
| Docker CE | Container runtime | No |
| Docker Compose | Container orchestration | No |
| Portainer CE | Web-based Docker management | No |
| Nginx Proxy Manager | Reverse proxy with Let's Encrypt SSL | **Yes** |
| UFW Firewall | Ports 22, 80, 443 | Yes |

## Architecture

### With NPM (Full Setup)

```
Internet (ports 80, 443)
    │
    ▼
┌───────────────────────────────────────┐
│  Nginx Proxy Manager                  │
│  - SSL termination (Let's Encrypt)    │
│  - Reverse proxy                      │
│  - Web UI on port 81 (internal)       │
└──────────────┬────────────────────────┘
               │ proxy-network
    ┌──────────┴──────────┐
    ▼                     ▼
┌──────────┐      ┌──────────────────┐
│Portainer │      │ Your Containers  │
│ (9443)   │      │                  │
└──────────┘      └──────────────────┘
```

### Without NPM (Minimal Setup)

```
┌───────────────────────────────────────┐
│  Docker Host                          │
│                                       │
│  ┌──────────┐    ┌──────────────────┐ │
│  │Portainer │    │ Your Containers  │ │
│  │ (9443)   │    │                  │ │
│  └──────────┘    └──────────────────┘ │
│         proxy-network                 │
└───────────────────────────────────────┘
```

## Configuration Options

The script will prompt for:

| Option | Default | Description |
|--------|---------|-------------|
| Hostname | Current hostname | Fully qualified domain name |
| Data directory | Auto-detected* | Persistent storage location |
| Timezone | Current timezone | Server timezone |
| UFW Firewall | Yes | Configure firewall rules |
| Docker network | `proxy-network` | Network for proxied containers |
| Compose directory | `~/docker-compose` | Location for compose files |
| **Install NPM** | **Yes** | **Install Nginx Proxy Manager** |

### Data Directory Auto-Detection

The script intelligently detects your storage setup:

- **Separate `/data` mount**: If `/data` is a mounted partition (common in multi-drive setups), it uses `/data`
- **Existing `/data` directory**: If `/data` exists, it uses `/data`
- **Single-drive setup**: If neither exists, it defaults to `~/docker-data` to avoid filling the root filesystem

You can always override the default with any path you prefer.

## Post-Installation

### Nginx Proxy Manager (if installed)

1. Access: `http://YOUR-IP:81`
2. Default login: `admin@example.com` / `changeme`
3. Change credentials immediately
4. Add SSL certificates (Let's Encrypt)
5. Create proxy hosts for your services

### Portainer

**With NPM:**
1. Set up NPM proxy host first (scheme: https, hostname: portainer, port: 9443)
2. Access via your NPM proxy URL
3. Create admin account
4. Select "Get Started" for local Docker management

**Without NPM:**
1. Edit `~/docker-compose/portainer/docker-compose.yml`
2. Add ports section:
   ```yaml
   ports:
     - "9443:9443"
   ```
3. Run: `cd ~/docker-compose/portainer && docker compose up -d`
4. Access: `https://YOUR-IP:9443`

## Uninstalling NPM

If you no longer need Nginx Proxy Manager:

```bash
# Download script if needed
curl -fsSL https://raw.githubusercontent.com/GonzFC/DockerFromScratch/main/setup.sh -o setup.sh
chmod +x setup.sh

# Run uninstall
./setup.sh --uninstall-npm
```

The uninstall will:
- Stop and remove the NPM container
- Remove the compose directory
- Optionally remove NPM data (certificates, config)
- Optionally remove the NPM Docker image

## Installing NPM Later

If you initially skipped NPM but want to add it later:

```bash
./setup.sh
```

Run the script again and choose "Yes" when asked about installing NPM.

## Directory Structure

```
~/docker-compose/
├── portainer/
│   └── docker-compose.yml
└── npm/                        # Only if NPM installed
    └── docker-compose.yml

/data/
├── portainer/                  # Portainer data
└── npm/                        # Only if NPM installed
    ├── data/                   # NPM configuration
    └── letsencrypt/            # SSL certificates
```

## Useful Commands

```bash
# View running containers
docker ps

# View container logs
docker logs -f <container-name>

# Update containers
cd ~/docker-compose/portainer && docker compose pull && docker compose up -d
cd ~/docker-compose/npm && docker compose pull && docker compose up -d

# Clean up unused images
docker image prune -a

# Check disk usage
docker system df
```

## Docker 29+ Portainer Fix

Docker 29 changed the minimum API version to 1.44, which breaks Portainer 2.x. The script detects this and offers to apply a fix:

```
/etc/systemd/system/docker.service.d/override.conf
[Service]
Environment=DOCKER_MIN_API_VERSION=1.24
```

Reference: https://github.com/orgs/portainer/discussions/12926

## Security Recommendations

After verifying everything works:

1. **Remove NPM admin port exposure** (if using NPM):
   ```yaml
   # In ~/docker-compose/npm/docker-compose.yml
   ports:
     - "80:80"
     - "443:443"
     # - "81:81"  # Remove this
   ```

2. **Access all admin UIs through NPM proxy only**

3. **Use strong passwords** for NPM and Portainer

4. **Keep systems updated**:
   ```bash
   sudo apt update && sudo apt upgrade -y
   ```

## Troubleshooting

### Container won't start
```bash
docker logs <container-name>
docker inspect <container-name>
```

### Network connectivity issues
```bash
docker network inspect proxy-network
docker exec -it npm ping portainer
```

### Port conflicts
```bash
sudo ss -tlnp | grep -E ':(80|81|443|9443)'
```

### Disk space
```bash
df -h
docker system df
docker system prune -a
```

## License

MIT License - feel free to use and modify.

## Credits

Developed with assistance from [Claude Code](https://claude.ai/claude-code).
