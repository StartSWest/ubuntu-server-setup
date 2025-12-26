#!/usr/bin/env bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SWAP_SIZE="2G"

# Functions
log_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

log_success() {
    echo -e "${GREEN}✓${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
}

print_header() {
    clear
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}          UBUNTU SERVER SETUP FOR PRODUCTION${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Get server information
print_server_info() {
    log_info "Server Information:"
    echo "  OS: $(lsb_release -d | cut -f2)"
    echo "  Kernel: $(uname -r)"
    echo "  CPU Cores: $(nproc)"
    echo "  Total RAM: $(free -h | awk '/^Mem:/ {print $2}')"
    echo "  Disk Space: $(df -h / | awk 'NR==2 {print $4}') available"
    echo ""
}

# Update system packages
update_system() {
    log_info "Updating system packages..."

    export DEBIAN_FRONTEND=noninteractive

    apt-get update
    apt-get upgrade -y
    apt-get dist-upgrade -y

    log_success "System packages updated"
}

# Install essential packages
install_essentials() {
    log_info "Installing essential packages..."

    apt-get install -y \
        curl \
        wget \
        git \
        vim \
        nano \
        htop \
        ufw \
        fail2ban \
        unattended-upgrades \
        apt-transport-https \
        ca-certificates \
        gnupg \
        lsb-release \
        software-properties-common \
        net-tools \
        jq \
        build-essential

    log_success "Essential packages installed"
}

# Configure automatic security updates
configure_auto_updates() {
    log_info "Configuring automatic security updates..."

    cat > /etc/apt/apt.conf.d/50unattended-upgrades <<EOF
Unattended-Upgrade::Allowed-Origins {
    "\${distro_id}:\${distro_codename}-security";
    "\${distro_id}ESMApps:\${distro_codename}-apps-security";
    "\${distro_id}ESM:\${distro_codename}-infra-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
EOF

    cat > /etc/apt/apt.conf.d/20auto-upgrades <<EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF

    log_success "Automatic security updates configured"
}

# Create swap file if needed
create_swap() {
    log_info "Checking swap space..."

    if swapon --show | grep -q '/swapfile'; then
        log_warning "Swap file already exists, skipping"
        return
    fi

    if [[ $(free -m | awk '/^Swap:/ {print $2}') -gt 0 ]]; then
        log_warning "Swap already configured, skipping"
        return
    fi

    log_info "Creating ${SWAP_SIZE} swap file..."

    fallocate -l $SWAP_SIZE /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile

    # Make swap permanent
    if ! grep -q '/swapfile' /etc/fstab; then
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
    fi

    # Optimize swap usage
    sysctl vm.swappiness=10
    sysctl vm.vfs_cache_pressure=50

    cat >> /etc/sysctl.conf <<EOF
vm.swappiness=10
vm.vfs_cache_pressure=50
EOF

    log_success "Swap file created and configured"
}

# Install Docker and Docker Compose
install_docker() {
    log_info "Installing Docker..."

    # Remove old versions
    apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true

    # Add Docker's official GPG key
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

    # Set up the repository
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Install Docker Engine
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    # Start and enable Docker
    systemctl start docker
    systemctl enable docker

    # Configure Docker daemon
    mkdir -p /etc/docker
    cat > /etc/docker/daemon.json <<EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF

    systemctl reload docker

    log_success "Docker installed and configured"
}


# Configure firewall
configure_firewall() {
    log_info "Configuring firewall (UFW)..."

    # Reset firewall
    ufw --force reset

    # Set default policies
    ufw default deny incoming
    ufw default allow outgoing

    # Allow SSH (check if custom port is being used)
    SSH_PORT=$(grep "^Port " /etc/ssh/sshd_config | awk '{print $2}' || echo "22")
    ufw allow $SSH_PORT/tcp comment 'SSH'

    # Allow HTTP and HTTPS
    ufw allow 80/tcp comment 'HTTP'
    ufw allow 443/tcp comment 'HTTPS'

    # Enable firewall
    ufw --force enable

    log_success "Firewall configured and enabled"
}

# Configure fail2ban
configure_fail2ban() {
    log_info "Configuring fail2ban..."

    # Create local configuration
    cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
bantime  = 1h
findtime  = 10m
maxretry = 5
destemail = root@localhost
sendername = Fail2Ban

[sshd]
enabled = true
port = ssh
logpath = %(sshd_log)s
backend = systemd

[nginx-http-auth]
enabled = true
port = http,https
logpath = /var/log/nginx/error.log

[nginx-limit-req]
enabled = true
port = http,https
logpath = /var/log/nginx/error.log
maxretry = 10
EOF

    systemctl restart fail2ban
    systemctl enable fail2ban

    log_success "Fail2ban configured and enabled"
}

# Harden SSH configuration
harden_ssh() {
    log_info "Hardening SSH configuration..."

    # Backup original config
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup

    # Create new SSH config
    cat > /etc/ssh/sshd_config.d/99-hardening.conf <<EOF
# Hardened SSH Configuration
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
ChallengeResponseAuthentication no
UsePAM yes
X11Forwarding no
PrintMotd no
AcceptEnv LANG LC_*
ClientAliveInterval 300
ClientAliveCountMax 2
MaxAuthTries 3
MaxSessions 5
Protocol 2
EOF

    log_warning "SSH hardening applied. Make sure you have SSH keys configured!"
    log_warning "Root login will be disabled after restart."

    # Test SSH configuration
    sshd -t

    log_success "SSH configuration hardened (restart SSH to apply)"
}



# Install and configure Nginx (system-level)
install_nginx() {
    log_info "Installing system Nginx..."

    apt-get install -y nginx

    # Stop nginx for now (we'll use Docker nginx)
    systemctl stop nginx
    systemctl disable nginx

    log_success "Nginx installed (will use Docker nginx)"
}

# Configure system limits
configure_limits() {
    log_info "Configuring system limits..."

    # Skip per-user limits - will be configured per-project
    # Projects should add their own limits in /etc/security/limits.d/

    cat >> /etc/sysctl.conf <<EOF

# Network optimizations
net.core.somaxconn = 1024
net.ipv4.tcp_max_syn_backlog = 2048
net.ipv4.ip_local_port_range = 10000 65000
net.ipv4.tcp_fin_timeout = 30
EOF

    sysctl -p

    log_success "System limits configured"
}

# Install monitoring tools
install_monitoring() {
    log_info "Installing monitoring tools..."

    apt-get install -y \
        netdata \
        iotop \
        iftop \
        ncdu

    # Configure netdata
    systemctl enable netdata
    systemctl start netdata

    log_success "Monitoring tools installed"
    log_info "Netdata dashboard: http://$(hostname -I | awk '{print $1}'):19999"
}

# Set up log rotation
configure_logrotate() {
    log_info "Configuring log rotation..."

    # Configure system log rotation
    cat > /etc/logrotate.d/docker-containers <<EOF
# Docker container logs
/var/lib/docker/containers/*/*.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    copytruncate
}
EOF

    log_success "Log rotation configured for Docker containers"
    log_info "Project-specific log rotation should be configured per-project"
}

# Set hostname
configure_hostname() {
    log_info "Current hostname: $(hostname)"

    read -p "Enter new hostname (or press Enter to skip): " new_hostname

    if [[ -n "$new_hostname" ]]; then
        hostnamectl set-hostname "$new_hostname"

        # Update hosts file
        sed -i "s/127.0.1.1.*/127.0.1.1 $new_hostname/" /etc/hosts

        log_success "Hostname set to: $new_hostname"
    else
        log_info "Hostname unchanged"
    fi
}

# Set timezone
configure_timezone() {
    log_info "Current timezone: $(timedatectl | grep "Time zone" | awk '{print $3}')"

    read -p "Enter timezone (e.g., America/New_York) or press Enter to skip: " new_timezone

    if [[ -n "$new_timezone" ]]; then
        timedatectl set-timezone "$new_timezone"
        log_success "Timezone set to: $new_timezone"
    else
        log_info "Timezone unchanged"
    fi
}

# Create welcome message
create_motd() {
    log_info "Creating custom welcome message..."

    cat > /etc/motd <<'EOF'

╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║            Production Server - Ready for Deploy          ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝

Quick Commands:
  - Check Docker:      docker ps
  - System stats:      htop
  - Disk usage:        df -h
  - Firewall status:   sudo ufw status
  - Netdata:           http://SERVER_IP:19999

Next Steps:
  1. Run setup-project.sh to configure your project
  2. Each project will have its own user and directory

EOF

    log_success "Custom welcome message created"
}

# Print summary and next steps
print_summary() {
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}           SERVER SETUP COMPLETE!${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    log_success "Server is ready for project deployment"
    echo ""
    echo "Summary:"
    echo "  ✓ System updated and secured"
    echo "  ✓ Docker installed and configured"
    echo "  ✓ Nginx installed"
    echo "  ✓ Firewall configured (ports 22, 80, 443)"
    echo "  ✓ Fail2ban enabled for intrusion prevention"
    echo "  ✓ SSH hardened (password auth disabled)"
    echo "  ✓ Swap file created: $SWAP_SIZE"
    echo "  ✓ System limits configured"
    echo "  ✓ Log rotation configured"
    if command -v netdata &> /dev/null; then
        echo "  ✓ Monitoring tools installed"
    fi
    echo ""

    log_warning "IMPORTANT: Next Steps"
    echo ""
    echo "1. Set up your project using the setup-project.sh script:"
    echo "   sudo bash setup-project.sh"
    echo ""
    echo "2. The project setup script will:"
    echo "   - Create a project-specific user"
    echo "   - Generate SSH keys for GitHub access"
    echo "   - Clone your repository"
    echo "   - Set up project directories"
    echo ""

    log_info "Server Information:"
    echo "  Server IP: $(hostname -I | awk '{print $1}')"
    if command -v netdata &> /dev/null; then
        echo "  Netdata Monitoring: http://$(hostname -I | awk '{print $1}'):19999"
    fi
    echo ""

    log_info "For SSL/HTTPS setup, the setup-project.sh script can configure Let's Encrypt certificates."
    echo ""
}

# Main setup function
main() {
    print_header

    check_root
    print_server_info

    log_warning "This script will set up your server for production deployment."
    log_warning "It will modify system configuration, install packages, and configure security."
    echo ""
    read -p "Continue? (y/N) " -n 1 -r
    echo

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Setup cancelled"
        exit 0
    fi

    echo ""
    log_info "Starting server setup..."
    echo ""

    # Run setup steps
    configure_hostname
    configure_timezone
    update_system
    install_essentials
    configure_auto_updates
    create_swap
    install_docker
    install_nginx
    configure_firewall
    configure_fail2ban
    harden_ssh
    configure_limits
    configure_logrotate
    create_motd

    # Optional monitoring
    read -p "Install monitoring tools (netdata, htop, iotop)? (Y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        install_monitoring
    fi

    # Cleanup
    apt-get autoremove -y
    apt-get autoclean

    print_summary
}

# Run main function
main "$@"
