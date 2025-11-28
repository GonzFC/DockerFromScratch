#!/bin/bash
#
# DockerFromScratch - Idempotent Docker Host Setup
# Sets up Docker, Portainer CE, and optionally Nginx Proxy Manager on Ubuntu 24.04
#
# Usage: curl -fsSL https://raw.githubusercontent.com/GonzFC/DockerFromScratch/main/setup.sh | bash
#    or: bash setup.sh
#    or: bash setup.sh --uninstall-npm
#
# Repository: https://github.com/GonzFC/DockerFromScratch
#

set -e

#=============================================================================
# COLORS AND FORMATTING
#=============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

#=============================================================================
# GLOBAL VARIABLES
#=============================================================================
SCRIPT_MODE="install"
CONFIG_INSTALL_NPM="y"

#=============================================================================
# HELPER FUNCTIONS
#=============================================================================
print_header() {
    echo ""
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC} ${BOLD}$1${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
}

print_step() {
    echo -e "${CYAN}▶${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

ask_yes_no() {
    local prompt="$1"
    local default="${2:-y}"
    local answer

    if [[ "$default" == "y" ]]; then
        prompt="$prompt [Y/n]: "
    else
        prompt="$prompt [y/N]: "
    fi

    read -r -p "$prompt" answer
    answer="${answer:-$default}"

    [[ "$answer" =~ ^[Yy]$ ]]
}

ask_input() {
    local prompt="$1"
    local default="$2"
    local answer

    if [[ -n "$default" ]]; then
        read -r -p "$prompt [$default]: " answer
        echo "${answer:-$default}"
    else
        read -r -p "$prompt: " answer
        echo "$answer"
    fi
}

check_root() {
    if [[ $EUID -eq 0 ]]; then
        print_error "This script should NOT be run as root. Run as a regular user with sudo privileges."
        exit 1
    fi

    if ! sudo -v &>/dev/null; then
        print_error "This script requires sudo privileges. Please ensure your user can use sudo."
        exit 1
    fi
}

check_ubuntu() {
    if [[ ! -f /etc/os-release ]]; then
        print_error "Cannot determine OS. This script requires Ubuntu 24.04."
        exit 1
    fi

    source /etc/os-release
    if [[ "$ID" != "ubuntu" ]]; then
        print_error "This script requires Ubuntu. Detected: $ID"
        exit 1
    fi

    if [[ "$VERSION_ID" != "24.04" ]]; then
        print_warning "This script is designed for Ubuntu 24.04. Detected: $VERSION_ID"
        if ! ask_yes_no "Continue anyway?" "n"; then
            exit 1
        fi
    fi
}

show_usage() {
    cat <<EOF
DockerFromScratch - Idempotent Docker Host Setup

Usage: $0 [OPTIONS]

OPTIONS:
    --help              Show this help message
    --uninstall-npm     Uninstall Nginx Proxy Manager

EXAMPLES:
    $0                  Run interactive setup
    $0 --uninstall-npm  Remove NPM container and data

EOF
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help|-h)
                show_usage
                exit 0
                ;;
            --uninstall-npm)
                SCRIPT_MODE="uninstall-npm"
                shift
                ;;
            *)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

#=============================================================================
# UNINSTALL FUNCTIONS
#=============================================================================
uninstall_npm() {
    print_header "Uninstall Nginx Proxy Manager"

    echo ""
    print_warning "This will remove the NPM container and optionally its data."
    echo ""

    # Try to find NPM compose directory
    local npm_dirs=(
        "$HOME/docker-compose/npm"
        "/home/$USER/docker-compose/npm"
    )

    local NPM_DIR=""
    for dir in "${npm_dirs[@]}"; do
        if [[ -f "$dir/docker-compose.yml" ]]; then
            NPM_DIR="$dir"
            break
        fi
    done

    # Check if NPM container exists
    if ! docker ps -a --format '{{.Names}}' | grep -q '^npm$'; then
        print_info "NPM container not found."

        if [[ -z "$NPM_DIR" ]]; then
            print_info "No NPM installation detected."
            return
        fi
    fi

    # Ask for confirmation
    if ! ask_yes_no "Are you sure you want to uninstall Nginx Proxy Manager?" "n"; then
        print_info "Uninstall cancelled."
        return
    fi

    # Stop and remove container
    if docker ps -a --format '{{.Names}}' | grep -q '^npm$'; then
        print_step "Stopping NPM container..."
        docker stop npm 2>/dev/null || true

        print_step "Removing NPM container..."
        docker rm npm 2>/dev/null || true
        print_success "NPM container removed"
    fi

    # Remove compose file
    if [[ -n "$NPM_DIR" ]] && [[ -f "$NPM_DIR/docker-compose.yml" ]]; then
        print_step "Removing compose directory..."
        rm -rf "$NPM_DIR"
        print_success "Compose directory removed: $NPM_DIR"
    fi

    # Ask about data removal
    echo ""
    local data_dirs=(
        "/data/npm"
    )

    for data_dir in "${data_dirs[@]}"; do
        if [[ -d "$data_dir" ]]; then
            print_warning "NPM data directory found: $data_dir"

            if ask_yes_no "Remove NPM data (certificates, config)? THIS CANNOT BE UNDONE!" "n"; then
                print_step "Removing NPM data..."
                sudo rm -rf "$data_dir"
                print_success "NPM data removed: $data_dir"
            else
                print_info "NPM data preserved at: $data_dir"
            fi
        fi
    done

    # Remove NPM image (optional)
    echo ""
    if docker images | grep -q "jc21/nginx-proxy-manager"; then
        if ask_yes_no "Remove NPM Docker image to free disk space?" "y"; then
            print_step "Removing NPM image..."
            docker rmi jc21/nginx-proxy-manager:latest 2>/dev/null || true
            print_success "NPM image removed"
        fi
    fi

    print_header "NPM Uninstall Complete"
    echo ""
    print_success "Nginx Proxy Manager has been uninstalled."
    echo ""
    print_info "If you had firewall rules for ports 80/443, you may want to remove them:"
    echo "  sudo ufw delete allow 80/tcp"
    echo "  sudo ufw delete allow 443/tcp"
    echo ""
}

#=============================================================================
# DRIVE DETECTION AND SETUP
#=============================================================================
detect_available_drives() {
    # Find block devices that are:
    # - Not mounted
    # - Not the boot/root disk
    # - Not partitions of mounted disks
    # - Not loop devices, ram disks, etc.

    local available_drives=()
    local root_disk=""

    # Find the disk that contains the root filesystem
    root_disk=$(lsblk -no PKNAME $(findmnt -n -o SOURCE /) 2>/dev/null | head -1)

    # List all block devices
    while IFS= read -r line; do
        local dev=$(echo "$line" | awk '{print $1}')
        local size=$(echo "$line" | awk '{print $2}')
        local type=$(echo "$line" | awk '{print $3}')
        local mountpoint=$(echo "$line" | awk '{print $4}')

        # Skip if it's a partition (we want whole disks)
        [[ "$type" != "disk" ]] && continue

        # Skip the root disk
        [[ "$dev" == "$root_disk" ]] && continue

        # Skip if any partition of this disk is mounted
        if lsblk -no MOUNTPOINT "/dev/$dev" 2>/dev/null | grep -q .; then
            continue
        fi

        # This is an available disk
        available_drives+=("$dev:$size")

    done < <(lsblk -dn -o NAME,SIZE,TYPE,MOUNTPOINT 2>/dev/null)

    # Return the list
    echo "${available_drives[@]}"
}

show_available_drives() {
    local drives=($1)

    if [[ ${#drives[@]} -eq 0 ]]; then
        return 1
    fi

    echo ""
    print_header "Available Drives Detected"
    echo ""
    print_info "The following unmounted drives were detected:"
    echo ""

    local i=1
    for drive_info in "${drives[@]}"; do
        local dev=$(echo "$drive_info" | cut -d: -f1)
        local size=$(echo "$drive_info" | cut -d: -f2)
        echo "  $i) /dev/$dev - $size"
        ((i++))
    done

    echo ""
    return 0
}

setup_new_drive() {
    local device="$1"
    local mount_point="$2"

    print_header "Setting Up Drive: /dev/$device"

    echo ""
    print_warning "This will ERASE ALL DATA on /dev/$device!"
    print_info "The drive will be formatted with ext4 and mounted at $mount_point"
    echo ""

    if ! ask_yes_no "Are you sure you want to format /dev/$device?" "n"; then
        print_info "Drive setup cancelled."
        return 1
    fi

    # Double confirmation for safety
    echo ""
    print_warning "FINAL WARNING: All data on /dev/$device will be permanently lost!"
    read -r -p "Type 'YES' to confirm: " confirm
    if [[ "$confirm" != "YES" ]]; then
        print_info "Drive setup cancelled."
        return 1
    fi

    echo ""
    print_step "Creating GPT partition table on /dev/$device..."
    sudo parted -s "/dev/$device" mklabel gpt
    if [[ $? -ne 0 ]]; then
        print_error "Failed to create partition table"
        return 1
    fi

    print_step "Creating partition..."
    sudo parted -s "/dev/$device" mkpart primary ext4 0% 100%
    if [[ $? -ne 0 ]]; then
        print_error "Failed to create partition"
        return 1
    fi

    # Wait for partition to appear
    sleep 2

    # Determine partition name (could be sdb1 or xvdb1 or nvme0n1p1)
    local partition=""
    if [[ -b "/dev/${device}1" ]]; then
        partition="${device}1"
    elif [[ -b "/dev/${device}p1" ]]; then
        partition="${device}p1"
    else
        print_error "Could not find the created partition"
        return 1
    fi

    print_step "Formatting /dev/$partition with ext4..."
    sudo mkfs.ext4 -F "/dev/$partition"
    if [[ $? -ne 0 ]]; then
        print_error "Failed to format partition"
        return 1
    fi

    print_step "Creating mount point at $mount_point..."
    sudo mkdir -p "$mount_point"

    print_step "Getting partition UUID..."
    local uuid=$(sudo blkid -s UUID -o value "/dev/$partition")
    if [[ -z "$uuid" ]]; then
        print_error "Could not get partition UUID"
        return 1
    fi

    print_step "Adding entry to /etc/fstab..."
    # Check if entry already exists
    if grep -q "$uuid" /etc/fstab; then
        print_info "Entry already exists in /etc/fstab"
    else
        echo "UUID=$uuid $mount_point ext4 defaults 0 2" | sudo tee -a /etc/fstab > /dev/null
    fi

    print_step "Mounting the drive..."
    sudo mount -a
    if [[ $? -ne 0 ]]; then
        print_error "Failed to mount drive"
        return 1
    fi

    # Verify mount
    if mountpoint -q "$mount_point"; then
        print_success "Drive successfully set up and mounted at $mount_point"

        # Set ownership
        sudo chown -R "$USER:$USER" "$mount_point"

        # Show result
        echo ""
        df -h "$mount_point"
        echo ""
        return 0
    else
        print_error "Drive setup completed but mount verification failed"
        return 1
    fi
}

offer_drive_setup() {
    # Detect available drives
    local drives_string=$(detect_available_drives)
    local drives=($drives_string)

    if [[ ${#drives[@]} -eq 0 ]]; then
        # No available drives found
        return 1
    fi

    show_available_drives "$drives_string"

    print_info "You can set up one of these drives for Docker data storage."
    print_info "This is recommended for production setups to separate data from the OS."
    echo ""

    if ! ask_yes_no "Would you like to set up a drive for /data?" "y"; then
        print_info "Skipping drive setup. You can set up a drive manually later."
        return 1
    fi

    # If only one drive, use it; otherwise ask
    local selected_drive=""
    if [[ ${#drives[@]} -eq 1 ]]; then
        selected_drive=$(echo "${drives[0]}" | cut -d: -f1)
    else
        echo ""
        read -r -p "Enter the number of the drive to use (1-${#drives[@]}): " selection

        if [[ "$selection" =~ ^[0-9]+$ ]] && [[ "$selection" -ge 1 ]] && [[ "$selection" -le ${#drives[@]} ]]; then
            selected_drive=$(echo "${drives[$((selection-1))]}" | cut -d: -f1)
        else
            print_error "Invalid selection"
            return 1
        fi
    fi

    # Set up the selected drive
    if setup_new_drive "$selected_drive" "/data"; then
        DRIVE_SETUP_SUCCESS=true
        return 0
    else
        return 1
    fi
}

#=============================================================================
# CONFIGURATION GATHERING
#=============================================================================
gather_configuration() {
    print_header "Configuration"

    echo ""
    print_info "Please provide the following configuration details."
    echo ""

    # Hostname
    CURRENT_HOSTNAME=$(hostname -f 2>/dev/null || hostname)
    CONFIG_HOSTNAME=$(ask_input "Fully qualified hostname" "$CURRENT_HOSTNAME")

    # Data directory - detect best default
    echo ""
    DEFAULT_DATA_DIR="/data"
    DRIVE_SETUP_SUCCESS=false

    # Check if /data exists as a mount point (separate partition/drive)
    if mountpoint -q /data 2>/dev/null; then
        print_info "Detected /data as a separate mount point."
        DEFAULT_DATA_DIR="/data"
    elif [[ -d /data ]]; then
        print_info "Directory /data exists."
        DEFAULT_DATA_DIR="/data"
    else
        # No /data mount - check for available drives
        print_info "No separate /data partition detected."

        # Offer to set up a new drive if available
        if offer_drive_setup; then
            DEFAULT_DATA_DIR="/data"
        else
            # No drive setup - suggest home directory for single-drive setups
            print_info "For single-drive setups, using home directory is recommended."
            DEFAULT_DATA_DIR="$HOME/docker-data"
        fi
    fi

    CONFIG_DATA_DIR=$(ask_input "Data directory for persistent storage" "$DEFAULT_DATA_DIR")

    # Warn if using root filesystem for /data
    if [[ "$CONFIG_DATA_DIR" == "/data" ]] && ! mountpoint -q /data 2>/dev/null; then
        if [[ ! -d /data ]]; then
            echo ""
            print_warning "/data will be created on the root filesystem."
            print_info "This is fine, but ensure your root partition has enough space."
            ROOT_FREE=$(df -h / | awk 'NR==2 {print $4}')
            print_info "Current free space on /: $ROOT_FREE"
            echo ""
        fi
    fi

    # Timezone
    CURRENT_TZ=$(timedatectl show --property=Timezone --value 2>/dev/null || echo "UTC")
    echo ""
    print_info "Common timezones: America/New_York, America/Los_Angeles, America/Mexico_City, Europe/London, UTC"
    CONFIG_TIMEZONE=$(ask_input "Timezone" "$CURRENT_TZ")

    # Firewall
    echo ""
    CONFIG_SETUP_UFW=$(ask_yes_no "Configure UFW firewall (ports 22, 80, 443)?" "y" && echo "y" || echo "n")

    # Docker network name
    CONFIG_NETWORK_NAME=$(ask_input "Docker network name for proxied containers" "proxy-network")

    # Compose directory
    CONFIG_COMPOSE_DIR=$(ask_input "Directory for docker-compose files" "$HOME/docker-compose")

    # NPM installation (optional)
    echo ""
    print_info "Nginx Proxy Manager provides reverse proxy with Let's Encrypt SSL."
    CONFIG_INSTALL_NPM=$(ask_yes_no "Install Nginx Proxy Manager?" "y" && echo "y" || echo "n")

    echo ""
    print_header "Configuration Summary"
    echo ""
    echo "  Hostname:        $CONFIG_HOSTNAME"
    echo "  Data directory:  $CONFIG_DATA_DIR"
    echo "  Timezone:        $CONFIG_TIMEZONE"
    echo "  UFW Firewall:    $CONFIG_SETUP_UFW"
    echo "  Docker network:  $CONFIG_NETWORK_NAME"
    echo "  Compose dir:     $CONFIG_COMPOSE_DIR"
    echo "  Install NPM:     $CONFIG_INSTALL_NPM"
    echo ""

    if ! ask_yes_no "Proceed with this configuration?" "y"; then
        print_info "Exiting. Run the script again to reconfigure."
        exit 0
    fi
}

#=============================================================================
# SYSTEM PREPARATION
#=============================================================================
setup_hostname() {
    print_step "Setting hostname to $CONFIG_HOSTNAME..."

    CURRENT=$(hostname -f 2>/dev/null || hostname)
    if [[ "$CURRENT" == "$CONFIG_HOSTNAME" ]]; then
        print_success "Hostname already set to $CONFIG_HOSTNAME"
    else
        sudo hostnamectl set-hostname "$CONFIG_HOSTNAME"
        print_success "Hostname set to $CONFIG_HOSTNAME"
    fi
}

setup_timezone() {
    print_step "Setting timezone to $CONFIG_TIMEZONE..."

    CURRENT=$(timedatectl show --property=Timezone --value 2>/dev/null)
    if [[ "$CURRENT" == "$CONFIG_TIMEZONE" ]]; then
        print_success "Timezone already set to $CONFIG_TIMEZONE"
    else
        sudo timedatectl set-timezone "$CONFIG_TIMEZONE"
        print_success "Timezone set to $CONFIG_TIMEZONE"
    fi
}

update_system() {
    print_step "Updating system packages..."
    sudo apt update
    sudo apt upgrade -y
    print_success "System packages updated"
}

install_dependencies() {
    print_step "Installing essential packages..."

    PACKAGES="curl wget git htop nano ca-certificates gnupg lsb-release"

    if [[ "$CONFIG_SETUP_UFW" == "y" ]]; then
        PACKAGES="$PACKAGES ufw"
    fi

    sudo apt install -y $PACKAGES
    print_success "Essential packages installed"
}

setup_data_directory() {
    print_step "Setting up data directory at $CONFIG_DATA_DIR..."

    if [[ -d "$CONFIG_DATA_DIR" ]]; then
        print_success "Data directory already exists"
    else
        sudo mkdir -p "$CONFIG_DATA_DIR"
        print_success "Created $CONFIG_DATA_DIR"
    fi

    # Create subdirectories
    sudo mkdir -p "$CONFIG_DATA_DIR/portainer"

    if [[ "$CONFIG_INSTALL_NPM" == "y" ]]; then
        sudo mkdir -p "$CONFIG_DATA_DIR/npm/data"
        sudo mkdir -p "$CONFIG_DATA_DIR/npm/letsencrypt"
    fi

    # Set ownership
    sudo chown -R "$USER:$USER" "$CONFIG_DATA_DIR"
    print_success "Data directory structure created and ownership set"
}

setup_firewall() {
    if [[ "$CONFIG_SETUP_UFW" != "y" ]]; then
        print_info "Skipping firewall configuration"
        return
    fi

    print_step "Configuring UFW firewall..."

    # Check if UFW is already enabled
    if sudo ufw status | grep -q "Status: active"; then
        print_info "UFW is already active, adding rules..."
    else
        sudo ufw default deny incoming
        sudo ufw default allow outgoing
    fi

    # Add rules (idempotent)
    sudo ufw allow 22/tcp comment 'SSH' 2>/dev/null || true

    if [[ "$CONFIG_INSTALL_NPM" == "y" ]]; then
        sudo ufw allow 80/tcp comment 'HTTP' 2>/dev/null || true
        sudo ufw allow 443/tcp comment 'HTTPS' 2>/dev/null || true
    fi

    # Enable UFW
    echo "y" | sudo ufw enable 2>/dev/null || true

    if [[ "$CONFIG_INSTALL_NPM" == "y" ]]; then
        print_success "UFW configured (ports 22, 80, 443 open)"
    else
        print_success "UFW configured (port 22 open)"
    fi
}

#=============================================================================
# DOCKER INSTALLATION
#=============================================================================
install_docker() {
    print_header "Docker Installation"

    # Check if Docker is already installed
    if command -v docker &>/dev/null; then
        DOCKER_VERSION=$(docker --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' | head -1)
        print_success "Docker is already installed (version $DOCKER_VERSION)"

        # Check for Docker 29+ Portainer compatibility
        check_docker_portainer_compat
        return
    fi

    print_step "Removing old Docker packages (if any)..."
    sudo apt remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true

    print_step "Adding Docker repository..."
    sudo install -m 0755 -d /etc/apt/keyrings

    if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        sudo chmod a+r /etc/apt/keyrings/docker.gpg
    fi

    ARCH=$(dpkg --print-architecture)
    CODENAME=$(. /etc/os-release && echo "$VERSION_CODENAME")

    echo "deb [arch=$ARCH signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $CODENAME stable" | \
        sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    print_step "Installing Docker..."
    sudo apt update
    sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    print_step "Adding user to docker group..."
    sudo usermod -aG docker "$USER"

    print_step "Configuring Docker daemon..."
    if [[ ! -f /etc/docker/daemon.json ]]; then
        sudo tee /etc/docker/daemon.json > /dev/null <<'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2"
}
EOF
    fi

    print_step "Enabling Docker services..."
    sudo systemctl enable docker
    sudo systemctl enable containerd
    sudo systemctl restart docker

    print_success "Docker installed successfully"

    # Check for Docker 29+ Portainer compatibility
    check_docker_portainer_compat
}

check_docker_portainer_compat() {
    DOCKER_MAJOR=$(docker --version 2>/dev/null | grep -oP '\d+' | head -1)

    if [[ "$DOCKER_MAJOR" -ge 29 ]]; then
        print_warning "Docker $DOCKER_MAJOR detected. Portainer may have compatibility issues."

        # Check if fix is already applied
        if [[ -f /etc/systemd/system/docker.service.d/override.conf ]]; then
            if grep -q "DOCKER_MIN_API_VERSION=1.24" /etc/systemd/system/docker.service.d/override.conf; then
                print_success "Portainer compatibility fix already applied"
                return
            fi
        fi

        echo ""
        print_info "Docker 29+ changed the minimum API version, which breaks Portainer 2.x."
        print_info "A fix is available that sets DOCKER_MIN_API_VERSION=1.24"
        echo ""

        if ask_yes_no "Apply Portainer compatibility fix?" "y"; then
            sudo mkdir -p /etc/systemd/system/docker.service.d
            sudo tee /etc/systemd/system/docker.service.d/override.conf > /dev/null <<'EOF'
[Service]
Environment=DOCKER_MIN_API_VERSION=1.24
EOF
            sudo systemctl daemon-reload
            sudo systemctl restart docker
            print_success "Portainer compatibility fix applied"
        else
            print_warning "Skipping fix. Portainer may not work correctly."
        fi
    fi
}

setup_docker_network() {
    print_step "Creating Docker network '$CONFIG_NETWORK_NAME'..."

    if docker network ls | grep -q "$CONFIG_NETWORK_NAME"; then
        print_success "Network '$CONFIG_NETWORK_NAME' already exists"
    else
        docker network create "$CONFIG_NETWORK_NAME"
        print_success "Network '$CONFIG_NETWORK_NAME' created"
    fi
}

#=============================================================================
# PORTAINER INSTALLATION
#=============================================================================
install_portainer() {
    print_header "Portainer CE Installation"

    PORTAINER_DIR="$CONFIG_COMPOSE_DIR/portainer"

    print_step "Creating Portainer compose directory..."
    mkdir -p "$PORTAINER_DIR"

    print_step "Creating docker-compose.yml..."
    cat > "$PORTAINER_DIR/docker-compose.yml" <<EOF
services:
  portainer:
    image: portainer/portainer-ce:latest
    container_name: portainer
    restart: unless-stopped
    command: -H unix:///var/run/docker.sock
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - $CONFIG_DATA_DIR/portainer:/data
    networks:
      - $CONFIG_NETWORK_NAME

networks:
  $CONFIG_NETWORK_NAME:
    external: true
EOF

    print_step "Deploying Portainer..."
    cd "$PORTAINER_DIR"
    docker compose pull
    docker compose up -d

    print_success "Portainer deployed successfully"
}

#=============================================================================
# NGINX PROXY MANAGER INSTALLATION
#=============================================================================
install_npm() {
    print_header "Nginx Proxy Manager Installation"

    NPM_DIR="$CONFIG_COMPOSE_DIR/npm"

    print_step "Creating NPM compose directory..."
    mkdir -p "$NPM_DIR"

    print_step "Creating docker-compose.yml..."
    cat > "$NPM_DIR/docker-compose.yml" <<EOF
services:
  npm:
    image: jc21/nginx-proxy-manager:latest
    container_name: npm
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
      - "81:81"
    volumes:
      - $CONFIG_DATA_DIR/npm/data:/data
      - $CONFIG_DATA_DIR/npm/letsencrypt:/etc/letsencrypt
    networks:
      - $CONFIG_NETWORK_NAME
    environment:
      - TZ=$CONFIG_TIMEZONE

networks:
  $CONFIG_NETWORK_NAME:
    external: true
EOF

    print_step "Deploying Nginx Proxy Manager..."
    cd "$NPM_DIR"
    docker compose pull
    docker compose up -d

    # Wait for NPM to be ready
    print_step "Waiting for NPM to start..."
    sleep 10

    print_success "Nginx Proxy Manager deployed successfully"
}

#=============================================================================
# VERIFICATION
#=============================================================================
verify_installation() {
    print_header "Verification"

    local ALL_OK=true

    # Check Docker
    if systemctl is-active --quiet docker; then
        print_success "Docker service is running"
    else
        print_error "Docker service is not running"
        ALL_OK=false
    fi

    # Check Portainer
    if docker ps --format '{{.Names}}' | grep -q '^portainer$'; then
        print_success "Portainer container is running"
    else
        print_error "Portainer container is not running"
        ALL_OK=false
    fi

    # Check NPM (only if installed)
    if [[ "$CONFIG_INSTALL_NPM" == "y" ]]; then
        if docker ps --format '{{.Names}}' | grep -q '^npm$'; then
            print_success "NPM container is running"
        else
            print_error "NPM container is not running"
            ALL_OK=false
        fi
    else
        print_info "NPM not installed (skipped by user)"
    fi

    # Check network
    if docker network ls --format '{{.Name}}' | grep -q "^${CONFIG_NETWORK_NAME}$"; then
        print_success "Docker network '$CONFIG_NETWORK_NAME' exists"
    else
        print_error "Docker network '$CONFIG_NETWORK_NAME' not found"
        ALL_OK=false
    fi

    echo ""
    if [[ "$ALL_OK" == true ]]; then
        print_success "All components installed and running!"
    else
        print_error "Some components failed. Check the logs above."
    fi
}

#=============================================================================
# QUICK START GUIDES
#=============================================================================
print_npm_quickstart() {
    local IP=$(hostname -I | awk '{print $1}')

    print_header "Nginx Proxy Manager - Quick Start Guide"

    cat <<EOF

${BOLD}1. ACCESS NPM ADMIN${NC}
   Open in browser: ${CYAN}http://$IP:81${NC}

   Default credentials:
   • Email:    ${YELLOW}admin@example.com${NC}
   • Password: ${YELLOW}changeme${NC}

   You'll be prompted to change these on first login.

${BOLD}2. CREATE SSL CERTIFICATES${NC}
   a) Go to ${CYAN}SSL Certificates${NC} tab
   b) Click ${CYAN}Add SSL Certificate${NC} → ${CYAN}Let's Encrypt${NC}
   c) Enter your domain names (e.g., npm.yourdomain.com)
   d) Enter email for Let's Encrypt notifications
   e) Agree to Terms of Service
   f) Click ${CYAN}Save${NC}

   ${YELLOW}Note:${NC} Your domain must point to this server's public IP for HTTP validation.
   For wildcard certificates, use DNS challenge with your DNS provider.

${BOLD}3. CREATE PROXY HOSTS${NC}

   ${CYAN}For NPM itself:${NC}
   a) Go to ${CYAN}Hosts${NC} → ${CYAN}Proxy Hosts${NC} → ${CYAN}Add Proxy Host${NC}
   b) Domain: npm.yourdomain.com
   c) Scheme: http
   d) Forward Hostname: ${YELLOW}npm${NC}
   e) Forward Port: ${YELLOW}81${NC}
   f) Enable: Block Common Exploits, Websockets Support
   g) SSL tab: Select certificate, Force SSL, HTTP/2

   ${CYAN}For Portainer:${NC}
   a) Add another Proxy Host
   b) Domain: portainer.yourdomain.com
   c) Scheme: ${YELLOW}https${NC}
   d) Forward Hostname: ${YELLOW}portainer${NC}
   e) Forward Port: ${YELLOW}9443${NC}
   f) Enable: Block Common Exploits, Websockets Support
   g) SSL tab: Select certificate, Force SSL, HTTP/2

${BOLD}4. LOCK DOWN ACCESS (After proxy works)${NC}
   Edit ${CYAN}$CONFIG_COMPOSE_DIR/npm/docker-compose.yml${NC}
   Remove or comment out port 81:

   ports:
     - "80:80"
     - "443:443"
     # - "81:81"

   Then run: ${CYAN}cd $CONFIG_COMPOSE_DIR/npm && docker compose up -d${NC}

EOF
}

print_portainer_quickstart() {
    local IP=$(hostname -I | awk '{print $1}')

    print_header "Portainer CE - Quick Start Guide"

    if [[ "$CONFIG_INSTALL_NPM" == "y" ]]; then
        cat <<EOF

${BOLD}1. INITIAL ACCESS${NC}
   ${YELLOW}Important:${NC} Portainer has no exposed ports by default.

   Temporarily expose port 9443 to set up admin account:

   a) Edit ${CYAN}$CONFIG_COMPOSE_DIR/portainer/docker-compose.yml${NC}
   b) Add ports section:
      ${CYAN}ports:
        - "9443:9443"${NC}
   c) Run: ${CYAN}cd $CONFIG_COMPOSE_DIR/portainer && docker compose up -d${NC}
   d) Access: ${CYAN}https://$IP:9443${NC} (accept self-signed cert warning)

   ${YELLOW}Or${NC} set up NPM proxy first, then access via HTTPS proxy.

EOF
    else
        cat <<EOF

${BOLD}1. INITIAL ACCESS (No NPM installed)${NC}
   You need to expose Portainer's port to access the web UI.

   a) Edit ${CYAN}$CONFIG_COMPOSE_DIR/portainer/docker-compose.yml${NC}
   b) Add ports section under the portainer service:
      ${CYAN}ports:
        - "9443:9443"${NC}
   c) Run: ${CYAN}cd $CONFIG_COMPOSE_DIR/portainer && docker compose up -d${NC}
   d) Access: ${CYAN}https://$IP:9443${NC} (accept self-signed cert warning)

   ${YELLOW}Tip:${NC} To install NPM later, run this script again.

EOF
    fi

    cat <<EOF
${BOLD}2. CREATE ADMIN USER${NC}
   • Set username and strong password
   • Click "Create user"

${BOLD}3. CONNECT LOCAL ENVIRONMENT${NC}
   • Click "Get Started"
   • Click "local" to manage this Docker instance

${BOLD}4. ENABLE DARK THEME (optional)${NC}
   • Click user icon (top right)
   • Go to "My Account"
   • Toggle "Use dark theme"

${BOLD}5. COMMON TASKS${NC}

   ┌─────────────────────┬─────────────────────────────────────┐
   │ Action              │ Location                            │
   ├─────────────────────┼─────────────────────────────────────┤
   │ View containers     │ Home → local → Containers           │
   │ View images         │ Home → local → Images               │
   │ Deploy new stack    │ Home → local → Stacks → Add stack   │
   │ Container logs      │ Containers → (select) → Logs        │
   │ Container shell     │ Containers → (select) → Console     │
   └─────────────────────┴─────────────────────────────────────┘

EOF

    if [[ "$CONFIG_INSTALL_NPM" == "y" ]]; then
        cat <<EOF
${BOLD}6. REMOVE DIRECT ACCESS (After NPM proxy works)${NC}
   Remove the ports section from docker-compose.yml and redeploy.

EOF
    fi
}

print_final_summary() {
    local IP=$(hostname -I | awk '{print $1}')

    print_header "Installation Complete!"

    cat <<EOF

${GREEN}All components have been installed successfully!${NC}

${BOLD}SERVER DETAILS${NC}
  Hostname:    $CONFIG_HOSTNAME
  IP Address:  $IP
  Timezone:    $CONFIG_TIMEZONE

${BOLD}INSTALLED COMPONENTS${NC}
  • Docker CE with Compose plugin
  • Portainer CE (container management)
EOF

    if [[ "$CONFIG_INSTALL_NPM" == "y" ]]; then
        cat <<EOF
  • Nginx Proxy Manager (reverse proxy + SSL)
EOF
    fi

    cat <<EOF

${BOLD}DIRECTORIES${NC}
  Compose files: $CONFIG_COMPOSE_DIR
  Persistent data: $CONFIG_DATA_DIR

EOF

    if [[ "$CONFIG_INSTALL_NPM" == "y" ]]; then
        cat <<EOF
${BOLD}QUICK ACCESS${NC}
  NPM Admin:   http://$IP:81

${BOLD}NEXT STEPS${NC}
  1. Log into NPM and change default credentials
  2. Set up SSL certificates for your domains
  3. Create proxy hosts for NPM and Portainer
  4. Access Portainer through NPM proxy
  5. Lock down direct port access
EOF
    else
        cat <<EOF
${BOLD}NEXT STEPS${NC}
  1. Expose Portainer port 9443 in docker-compose.yml
  2. Access Portainer at https://$IP:9443
  3. Create admin user and configure Docker management

${BOLD}TO INSTALL NPM LATER${NC}
  Run this script again and choose to install NPM.
EOF
    fi

    cat <<EOF

${BOLD}USEFUL COMMANDS${NC}
  docker ps                              # List running containers
  docker compose -f <file> logs -f       # View container logs
  docker compose -f <file> pull && \\
    docker compose -f <file> up -d       # Update containers

EOF

    if [[ "$CONFIG_INSTALL_NPM" == "y" ]]; then
        cat <<EOF
${BOLD}TO UNINSTALL NPM${NC}
  bash setup.sh --uninstall-npm

EOF
    fi

    cat <<EOF
${YELLOW}Note:${NC} Log out and back in (or run 'newgrp docker') to use Docker without sudo.

EOF
}

#=============================================================================
# MAIN
#=============================================================================
print_banner() {
    echo -e "${BOLD}"
    cat <<'EOF'
  ____             _             _____                    ____                 _       _
 |  _ \  ___   ___| | _____ _ __|  ___| __ ___  _ __ ___ / ___|  ___ _ __ __ _| |_ ___| |__
 | | | |/ _ \ / __| |/ / _ \ '__| |_ | '__/ _ \| '_ ` _ \\___ \ / __| '__/ _` | __/ __| '_ \
 | |_| | (_) | (__|   <  __/ |  |  _|| | | (_) | | | | | |___) | (__| | | (_| | || (__| | | |
 |____/ \___/ \___|_|\_\___|_|  |_|  |_|  \___/|_| |_| |_|____/ \___|_|  \__,_|\__\___|_| |_|

EOF
    echo -e "${NC}"
    echo -e "${CYAN}Idempotent Docker Host Setup for Ubuntu 24.04${NC}"
    echo -e "${CYAN}https://github.com/GonzFC/DockerFromScratch${NC}"
    echo ""
}

main_install() {
    # Pre-flight checks
    check_root
    check_ubuntu

    # Gather configuration
    gather_configuration

    # System preparation
    print_header "System Preparation"
    setup_hostname
    setup_timezone
    update_system
    install_dependencies
    setup_data_directory
    setup_firewall

    # Docker installation
    install_docker
    setup_docker_network

    # Application installation
    install_portainer

    if [[ "$CONFIG_INSTALL_NPM" == "y" ]]; then
        install_npm
    fi

    # Verification
    verify_installation

    # Quick start guides
    if [[ "$CONFIG_INSTALL_NPM" == "y" ]]; then
        print_npm_quickstart
    fi
    print_portainer_quickstart
    print_final_summary
}

main() {
    # Parse command line arguments
    parse_arguments "$@"

    clear
    print_banner

    case "$SCRIPT_MODE" in
        install)
            main_install
            ;;
        uninstall-npm)
            check_root
            uninstall_npm
            ;;
        *)
            print_error "Unknown mode: $SCRIPT_MODE"
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
