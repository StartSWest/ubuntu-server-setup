#!/usr/bin/env bash
set -euo pipefail

# ============================================
# SSH Hardening Script
# ============================================
# Run this AFTER you've deployed your applications and verified
# everything works. This script will disable password authentication.
#
# Usage: sudo ./harden-ssh.sh
#
# WARNING: Make sure you have SSH key access working before running!
# ============================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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
    echo -e "${BLUE}              SSH HARDENING SCRIPT${NC}"
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

# Setup SSH keys for root access
setup_root_ssh_keys() {
    echo ""
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "           SSH KEY SETUP FOR ROOT ACCESS"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    log_info "To secure your server, we'll set up SSH key authentication."
    log_warning "After this, password login will be disabled!"
    echo ""

    # Create SSH directory for root if it doesn't exist
    mkdir -p /root/.ssh
    chmod 700 /root/.ssh
    touch /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys

    # Check if authorized_keys already has keys
    if [[ -s /root/.ssh/authorized_keys ]]; then
        log_success "SSH keys already configured for root"
        log_info "Current authorized keys:"
        cat /root/.ssh/authorized_keys
        echo ""
        read -p "Do you want to add more keys? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return 0
        fi
    fi

    echo ""
    log_info "On your LOCAL MACHINE, generate an SSH key if you don't have one:"
    echo ""
    echo -e "${GREEN}  ssh-keygen -t ed25519 -C \"your_email@example.com\"${NC}"
    echo ""
    log_info "Then display your public key:"
    echo ""
    echo -e "${GREEN}  cat ~/.ssh/id_ed25519.pub${NC}"
    echo ""
    echo -e "${YELLOW}Or if you have an RSA key:${NC}"
    echo -e "${GREEN}  cat ~/.ssh/id_rsa.pub${NC}"
    echo ""

    log_warning "PASTE YOUR PUBLIC SSH KEY BELOW"
    log_info "It should start with 'ssh-ed25519' or 'ssh-rsa'"
    echo ""
    echo -n "Paste your public key here: "
    read ssh_public_key

    if [[ -z "$ssh_public_key" ]]; then
        log_error "No SSH key provided"
        log_warning "Skipping SSH key setup - you'll need to configure this manually"
        return 1
    fi

    # Validate the key format
    if [[ ! "$ssh_public_key" =~ ^(ssh-rsa|ssh-ed25519|ecdsa-sha2-nistp256) ]]; then
        log_error "Invalid SSH key format"
        log_info "Key should start with 'ssh-rsa', 'ssh-ed25519', or 'ecdsa-sha2-nistp256'"
        return 1
    fi

    # Add the key to authorized_keys
    log_info "Adding key to /root/.ssh/authorized_keys..."
    echo "$ssh_public_key" >> /root/.ssh/authorized_keys
    log_success "SSH key added to root's authorized_keys"

    # Show what was added
    echo ""
    log_info "Key added:"
    echo "  $ssh_public_key"

    echo ""
    log_info "Testing SSH key authentication..."
    log_warning "IMPORTANT: Open a NEW terminal window and test SSH connection:"
    echo ""
    echo -e "${GREEN}  ssh root@$(hostname -I | awk '{print $1}')${NC}"
    echo ""
    log_warning "DO NOT CLOSE THIS TERMINAL until you've verified SSH key login works!"
    echo ""
    read -p "Press ENTER after you've successfully tested SSH key login in another terminal... " -r

    log_success "SSH key setup complete"
    return 0
}

# Harden SSH configuration
harden_ssh() {
    echo ""
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_warning "SSH SECURITY HARDENING"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    log_info "SSH hardening will:"
    echo "  • Disable password authentication (key-only access)"
    echo "  • Disable root login via SSH"
    echo "  • Enable additional security measures"
    echo ""

    log_warning "This is HIGHLY RECOMMENDED for production servers"
    echo ""

    read -p "Do you want to harden SSH configuration? (Y/n) " -n 1 -r
    echo

    if [[ $REPLY =~ ^[Nn]$ ]]; then
        log_warning "SSH hardening skipped - your server is less secure!"
        log_info "You can manually harden SSH later by editing /etc/ssh/sshd_config"
        return
    fi

    # Backup original config
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup

    # Create new SSH config
    cat > /etc/ssh/sshd_config.d/99-hardening.conf <<EOF
# Hardened SSH Configuration
PermitRootLogin prohibit-password
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

    # Test SSH configuration
    if ! sshd -t; then
        log_error "SSH configuration test failed!"
        rm /etc/ssh/sshd_config.d/99-hardening.conf
        log_info "Hardening config removed to prevent issues"
        return 1
    fi

    # Restart SSH to apply changes
    systemctl restart ssh

    log_success "SSH configuration hardened and applied"
    echo ""
    log_info "SSH hardening complete:"
    echo "  ✓ Password authentication disabled"
    echo "  ✓ Root can login with SSH keys only (prohibit-password)"
    echo "  ✓ Additional security measures enabled"
    echo ""

    log_warning "If you get locked out, use your hosting provider's console to:"
    echo "  1. Login via console/VNC"
    echo "  2. Run: rm /etc/ssh/sshd_config.d/99-hardening.conf"
    echo "  3. Run: systemctl restart ssh"
    echo ""
}

# Print summary
print_summary() {
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}           SSH HARDENING COMPLETE!${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    log_success "Your server SSH is now hardened"
    echo ""
    echo "Changes made:"
    echo "  ✓ SSH key authentication configured"
    echo "  ✓ Password authentication disabled"
    echo "  ✓ Root password login disabled (key only)"
    echo ""
    log_warning "Remember: You can only access the server with SSH keys now!"
    echo ""
}

# Main function
main() {
    print_header

    check_root

    log_warning "This script will harden SSH and disable password authentication."
    log_warning "Make sure you have SSH key access working before proceeding!"
    echo ""
    log_info "Run this script AFTER:"
    echo "  1. Your applications are deployed and working"
    echo "  2. You've tested everything with sudo access"
    echo "  3. You have SSH key authentication set up"
    echo ""

    read -p "Continue with SSH hardening? (y/N) " -n 1 -r
    echo

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "SSH hardening cancelled"
        exit 0
    fi

    # Run hardening steps
    setup_root_ssh_keys
    harden_ssh

    print_summary
}

# Run main function
main "$@"
