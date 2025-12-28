#!/usr/bin/env bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration (will be set dynamically)
PROJECT_NAME=""
APP_USER=""
APP_DIR=""
REPO_URL=""

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
    echo -e "${BLUE}            PROJECT SETUP FOR PRODUCTION SERVER${NC}"
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

# Get project information
get_project_info() {
    echo ""
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "               PROJECT CONFIGURATION"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Get project name
    read -p "Enter project name (e.g., my-app, api-service): " PROJECT_NAME

    if [[ -z "$PROJECT_NAME" ]]; then
        log_error "Project name is required"
        exit 1
    fi

    # Sanitize project name (lowercase, replace spaces with dashes)
    PROJECT_NAME=$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
    APP_DIR="/opt/$PROJECT_NAME"

    # Get username (optional, defaults to projectname-user)
    echo ""
    read -p "Enter username for this project [${PROJECT_NAME}-user]: " APP_USER_INPUT

    if [[ -z "$APP_USER_INPUT" ]]; then
        # If project name is simple, use it as username, otherwise use generic name
        if [[ ${#PROJECT_NAME} -le 12 ]]; then
            APP_USER="${PROJECT_NAME}-user"
        else
            APP_USER="app-user"
        fi
        log_info "Using default username: $APP_USER"
    else
        # Sanitize username (lowercase, alphanumeric and hyphens only)
        APP_USER=$(echo "$APP_USER_INPUT" | tr '[:upper:]' '[:lower:]' | tr -cd '[:alnum:]-')
    fi

    echo ""
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_success "Configuration Summary:"
    echo "  Project Name:   $PROJECT_NAME"
    echo "  Username:       $APP_USER"
    echo "  Install Path:   $APP_DIR"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

# Create application user
create_app_user() {
    log_info "Creating application user: $APP_USER..."

    # Check if user already exists
    if id "$APP_USER" &>/dev/null; then
        log_warning "User $APP_USER already exists"
        log_info "Do you want to continue with this user? (y/N)"
        read -r response
        if [[ ! $response =~ ^[Yy]$ ]]; then
            log_info "Setup cancelled"
            exit 0
        fi
    else
        # Create user with home directory
        useradd -m -s /bin/bash "$APP_USER"
        log_success "User $APP_USER created"
    fi

    # Add user to docker group if docker is installed
    if command -v docker &> /dev/null; then
        usermod -aG docker "$APP_USER"
        log_success "User added to docker group"
    fi

    # Configure passwordless sudo for deployment commands
    log_info "Configuring passwordless sudo for deployment..."

    cat > /etc/sudoers.d/${APP_USER}-deploy <<EOF
# Allow ${APP_USER} to run deployment commands without password
${APP_USER} ALL=(ALL) NOPASSWD: /usr/bin/chown -R 1001\:1001 ${APP_DIR}/public/uploads*
${APP_USER} ALL=(ALL) NOPASSWD: /usr/bin/chmod -R 755 ${APP_DIR}/public/uploads*
${APP_USER} ALL=(ALL) NOPASSWD: /usr/bin/docker *
${APP_USER} ALL=(ALL) NOPASSWD: /usr/bin/docker-compose *
EOF

    # Set proper permissions on sudoers file
    chmod 0440 /etc/sudoers.d/${APP_USER}-deploy

    # Validate sudoers file
    if visudo -c -f /etc/sudoers.d/${APP_USER}-deploy &>/dev/null; then
        log_success "Passwordless sudo configured for deployment"
    else
        log_error "Sudoers file validation failed"
        rm -f /etc/sudoers.d/${APP_USER}-deploy
        log_warning "Continuing without passwordless sudo (you'll need to enter password during deployment)"
    fi

    # Create SSH directory
    mkdir -p /home/$APP_USER/.ssh
    chmod 700 /home/$APP_USER/.ssh
    touch /home/$APP_USER/.ssh/authorized_keys
    chmod 600 /home/$APP_USER/.ssh/authorized_keys
    chown -R $APP_USER:$APP_USER /home/$APP_USER/.ssh

    log_success "SSH directory created"
}

# Setup GitHub SSH key
setup_github_ssh() {
    log_info "Setting up GitHub SSH access for $APP_USER..."

    local ssh_key_path="/home/$APP_USER/.ssh/id_ed25519"

    # Check if SSH key already exists
    if [[ -f "$ssh_key_path" ]]; then
        log_warning "SSH key already exists for $APP_USER"
        log_info "Do you want to display it again? (y/N)"
        read -r response
        if [[ ! $response =~ ^[Yy]$ ]]; then
            return
        fi
    else
        # Generate SSH key
        log_info "Generating SSH key for GitHub..."
        sudo -u "$APP_USER" ssh-keygen -t ed25519 -C "$APP_USER@$(hostname)" -f "$ssh_key_path" -N ""
        log_success "SSH key generated"
    fi

    # Display the public key
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}           GITHUB SSH KEY SETUP${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    log_info "Add this SSH key to your GitHub account:"
    echo ""
    echo -e "${GREEN}$(cat ${ssh_key_path}.pub)${NC}"
    echo ""
    echo -e "${YELLOW}Steps:${NC}"
    echo "  1. Copy the key above (including 'ssh-ed25519' and email)"
    echo "  2. Go to: https://github.com/settings/keys"
    echo "  3. Click 'New SSH key'"
    echo "  4. Title: '$PROJECT_NAME Production Server'"
    echo "  5. Paste the key"
    echo "  6. Click 'Add SSH key'"
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    log_warning "Press ENTER when you have added the key to GitHub..."
    read -r

    # Test GitHub connection
    log_info "Testing GitHub connection..."
    if sudo -u "$APP_USER" ssh -T git@github.com -o StrictHostKeyChecking=accept-new 2>&1 | grep -q "successfully authenticated"; then
        log_success "GitHub SSH connection successful!"
    else
        log_warning "GitHub connection test inconclusive (this is usually okay)"
        log_info "You can test later with: ssh -T git@github.com"
    fi

    echo ""
}

# Create application directory
setup_app_directory() {
    log_info "Setting up application directory: $APP_DIR..."

    # Check if directory already exists
    if [[ -d "$APP_DIR" ]]; then
        log_warning "Directory $APP_DIR already exists"
        log_info "Do you want to continue and potentially overwrite? (y/N)"
        read -r response
        if [[ ! $response =~ ^[Yy]$ ]]; then
            log_info "Setup cancelled"
            exit 0
        fi
    else
        # Create directory
        mkdir -p "$APP_DIR"
        log_success "Directory created"
    fi

    # Set ownership
    chown -R $APP_USER:$APP_USER "$APP_DIR"
    chmod 755 "$APP_DIR"

    log_success "Application directory configured"
}

# Clone repository or copy current directory
clone_repository() {
    echo ""
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "               REPOSITORY SETUP"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    log_info "How do you want to set up the project?"
    echo ""
    echo "  1) Clone from GitHub/GitLab repository (recommended)"
    echo "  2) Copy from current directory (if running from project)"
    echo "  3) Skip for now (manual setup later)"
    echo ""
    read -p "Choose option [1-3]: " setup_option

    case $setup_option in
        1)
            # Clone from repository
            echo ""

            # Ask if repository is public or private
            log_info "Is your repository public or private?"
            echo "  1) Public (no authentication needed to pull)"
            echo "  2) Private (requires authentication)"
            read -p "Choose [1-2]: " repo_type

            echo ""
            if [[ "$repo_type" == "1" ]]; then
                # Public repository - use HTTPS
                log_info "For public repos, use HTTPS URL format:"
                echo "  Example: https://github.com/username/repo.git"
                read -p "Enter repository URL: " REPO_URL

                if [[ -z "$REPO_URL" ]]; then
                    log_error "Repository URL is required"
                    exit 1
                fi

                log_info "Cloning public repository..."

                # Clone as the app user (no auth needed for public repos)
                if sudo -u "$APP_USER" git clone "$REPO_URL" "$APP_DIR" 2>&1; then
                    log_success "Repository cloned successfully"
                else
                    log_error "Failed to clone repository"
                    log_info "Make sure the repository URL is correct and accessible"
                    exit 1
                fi
            else
                # Private repository - use SSH
                log_info "For private repos, use SSH URL format:"
                echo "  Example: git@github.com:username/repo.git"
                read -p "Enter repository URL: " REPO_URL

                if [[ -z "$REPO_URL" ]]; then
                    log_error "Repository URL is required"
                    exit 1
                fi

                log_info "Cloning private repository..."

                # Clone as the app user
                if sudo -u "$APP_USER" git clone "$REPO_URL" "$APP_DIR" 2>&1; then
                    log_success "Repository cloned successfully"
                else
                    log_error "Failed to clone repository"
                    log_info "Make sure:"
                    echo "  1. The repository URL is correct"
                    echo "  2. You added the SSH key to GitHub/GitLab"
                    echo "  3. You have access to the repository"
                    exit 1
                fi
            fi
            ;;
        2)
            # Copy from current directory
            log_info "Copying files from current directory..."

            # Get current directory
            CURRENT_DIR=$(pwd)

            # Copy files
            if cp -r "$CURRENT_DIR"/* "$APP_DIR/" 2>/dev/null; then
                chown -R $APP_USER:$APP_USER "$APP_DIR"
                log_success "Files copied successfully"
            else
                log_error "Failed to copy files"
                exit 1
            fi
            ;;
        3)
            # Skip
            log_info "Skipping repository setup"
            log_warning "You'll need to manually clone/copy your project to: $APP_DIR"
            return
            ;;
        *)
            log_error "Invalid option"
            exit 1
            ;;
    esac

    # Check for .env.production.example
    if [[ -f "$APP_DIR/.env.production.example" ]]; then
        log_info "Creating .env.production from example..."
        sudo -u "$APP_USER" cp "$APP_DIR/.env.production.example" "$APP_DIR/.env.production"
        log_success "Environment file created"
        log_warning "Remember to edit $APP_DIR/.env.production with your actual values"
    fi
}

# Show completion summary
show_summary() {
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}           PROJECT SETUP COMPLETED SUCCESSFULLY!${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    log_info "Project Details:"
    echo "  Project:   $PROJECT_NAME"
    echo "  Username:  $APP_USER"
    echo "  Directory: $APP_DIR"
    echo ""

    log_warning "Next Steps:"
    echo ""
    echo "1. Configure environment variables (if not done already):"
    echo "   sudo -u $APP_USER nano $APP_DIR/.env.production"
    echo ""
    echo "2. Switch to project user:"
    echo "   sudo -u $APP_USER -i"
    echo "   cd $APP_DIR"
    echo ""
    echo "3. Run the deployment script (if available):"
    echo "   ./scripts/deploy.sh"
    echo ""
    echo "4. Or manually start your application:"
    echo "   docker-compose -f docker-compose.prod.yml up -d"
    echo ""

    log_info "Server IP: $(hostname -I | awk '{print $1}')"
    echo ""
}

# Main setup function
main() {
    print_header

    check_root

    log_warning "This script will set up a new project on this server."
    log_info "It will create a user, SSH keys, and clone your repository."
    echo ""
    read -p "Continue? (y/N) " -n 1 -r
    echo

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Setup cancelled"
        exit 0
    fi

    # Run setup steps
    get_project_info
    create_app_user

    # Ask if SSH keys are needed
    echo ""
    log_info "Do you need SSH keys for GitHub/GitLab access?"
    echo "  - Select YES if you have a private repository"
    echo "  - Select YES if you need to push changes"
    echo "  - Select NO if you only have public repositories and won't push"
    read -p "Set up SSH keys? (y/N): " setup_ssh

    if [[ $setup_ssh =~ ^[Yy]$ ]]; then
        setup_github_ssh
    else
        log_info "Skipping SSH key setup"
        log_info "You can set up SSH keys later if needed"
    fi

    setup_app_directory
    clone_repository
    show_summary

    log_success "Project setup complete!"
    echo ""
}

# Run main function
main "$@"
