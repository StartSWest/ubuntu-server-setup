#!/usr/bin/env bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}               SSL/HTTPS SETUP WITH LET'S ENCRYPT${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

print_section() {
    echo ""
    echo -e "${CYAN}▸ $1${NC}"
    echo ""
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Validate domain format
validate_domain() {
    local domain=$1
    if [[ ! $domain =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        log_error "Invalid domain format: $domain"
        return 1
    fi
    return 0
}

# Validate email format
validate_email() {
    local email=$1
    if [[ ! $email =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        log_error "Invalid email format: $email"
        return 1
    fi
    return 0
}

# Check if domain points to this server
check_dns() {
    local domain=$1
    local server_ip=$2

    log_info "Checking DNS configuration for $domain..."

    # Get both IPv4 (A) and IPv6 (AAAA) records
    local resolved_ipv4=$(dig +short A "$domain" @8.8.8.8 | grep -v '\.$' | head -n1)
    local resolved_ipv6=$(dig +short AAAA "$domain" @8.8.8.8 | grep -v '\.$' | head -n1)

    # Get server's IPv4 and IPv6 addresses
    local server_ipv4=$(curl -4 -s ifconfig.me 2>/dev/null || echo "")
    local server_ipv6=$(curl -6 -s ifconfig.me 2>/dev/null || echo "")

    log_info "Domain DNS records:"
    [[ -n "$resolved_ipv4" ]] && echo "  IPv4 (A):    $resolved_ipv4" || echo "  IPv4 (A):    Not set"
    [[ -n "$resolved_ipv6" ]] && echo "  IPv6 (AAAA): $resolved_ipv6" || echo "  IPv6 (AAAA): Not set"
    echo ""
    log_info "Server IP addresses:"
    [[ -n "$server_ipv4" ]] && echo "  IPv4: $server_ipv4" || echo "  IPv4: Not available"
    [[ -n "$server_ipv6" ]] && echo "  IPv6: $server_ipv6" || echo "  IPv6: Not available"
    echo ""

    # Check if domain resolves to at least one IP
    if [[ -z "$resolved_ipv4" && -z "$resolved_ipv6" ]]; then
        log_error "Domain $domain does not resolve to any IP address"
        return 1
    fi

    # Check if domain points to this server (IPv4 or IPv6)
    local match_found=false

    if [[ -n "$resolved_ipv4" && -n "$server_ipv4" && "$resolved_ipv4" == "$server_ipv4" ]]; then
        log_success "DNS correctly points to this server via IPv4 ($resolved_ipv4)"
        match_found=true
    fi

    if [[ -n "$resolved_ipv6" && -n "$server_ipv6" && "$resolved_ipv6" == "$server_ipv6" ]]; then
        log_success "DNS correctly points to this server via IPv6 ($resolved_ipv6)"
        match_found=true
    fi

    if [[ "$match_found" == "false" ]]; then
        log_error "Domain does not point to this server"
        log_warning "Update your DNS records to point to one of this server's IP addresses"
        return 1
    fi

    return 0
}

# Install certbot
install_certbot() {
    log_info "Checking for Certbot installation..."

    if command -v certbot &> /dev/null; then
        log_success "Certbot is already installed"
        return 0
    fi

    log_info "Installing Certbot..."
    apt-get update -qq
    apt-get install -y certbot

    log_success "Certbot installed successfully"
}

# Stop Docker services on port 80
stop_services() {
    local project_dir=$1

    log_info "Temporarily stopping nginx to free port 80..."

    cd "$project_dir"

    if [[ -f "docker-compose.prod.yml" ]]; then
        docker compose -f docker-compose.prod.yml stop nginx 2>/dev/null || docker-compose -f docker-compose.prod.yml stop nginx 2>/dev/null || true
    elif [[ -f "docker-compose.yml" ]]; then
        docker compose stop nginx 2>/dev/null || docker-compose stop nginx 2>/dev/null || true
    fi

    log_success "Nginx stopped"
}

# Start Docker services
start_services() {
    local project_dir=$1

    log_info "Starting services..."

    cd "$project_dir"

    if [[ -f "docker-compose.prod.yml" ]]; then
        docker compose -f docker-compose.prod.yml up -d 2>/dev/null || docker-compose -f docker-compose.prod.yml up -d
    elif [[ -f "docker-compose.yml" ]]; then
        docker compose up -d 2>/dev/null || docker-compose up -d
    fi

    log_success "Services started"
}

# Obtain SSL certificate
obtain_certificate() {
    local domain=$1
    local email=$2
    local include_www=$3

    log_info "Obtaining SSL certificate from Let's Encrypt..."

    local certbot_cmd="certbot certonly --standalone --non-interactive --agree-tos -m $email -d $domain"

    if [[ "$include_www" == "yes" ]]; then
        certbot_cmd="$certbot_cmd -d www.$domain"
    fi

    if $certbot_cmd; then
        log_success "SSL certificate obtained successfully"
        return 0
    else
        log_error "Failed to obtain SSL certificate"
        return 1
    fi
}

# Copy certificates to project
copy_certificates() {
    local domain=$1
    local project_dir=$2
    local project_user=$3

    log_info "Copying certificates to project directory..."

    local ssl_dir="$project_dir/ssl"
    mkdir -p "$ssl_dir"

    cp "/etc/letsencrypt/live/$domain/fullchain.pem" "$ssl_dir/cert.pem"
    cp "/etc/letsencrypt/live/$domain/privkey.pem" "$ssl_dir/key.pem"

    chown -R "$project_user:$project_user" "$ssl_dir"
    chmod 644 "$ssl_dir/cert.pem"
    chmod 600 "$ssl_dir/key.pem"

    log_success "Certificates copied to $ssl_dir"
}

# Update nginx configuration for HTTPS
update_nginx_config() {
    local project_dir=$1
    local domain=$2

    log_info "Updating nginx configuration for HTTPS..."

    local nginx_conf="$project_dir/nginx/nginx.conf"

    if [[ ! -f "$nginx_conf" ]]; then
        log_warning "nginx.conf not found at $nginx_conf"
        log_warning "You'll need to manually configure nginx for HTTPS"
        return 1
    fi

    # Create backup
    cp "$nginx_conf" "$nginx_conf.backup"

    # Enable HTTPS redirect (uncomment line 51 or similar)
    sed -i 's|^[ \t]*# return 301 https://\$host\$request_uri;|    return 301 https://\$host\$request_uri;|' "$nginx_conf"

    # Comment out HTTP location block
    sed -i '/^[ \t]*# For now, proxy to app/,/^[ \t]*}[ \t]*$/{s/^/#/}' "$nginx_conf"

    # Uncomment HTTPS server block
    sed -i '/^[ \t]*# server {/,/^[ \t]*# }/s/^[ \t]*# /    /' "$nginx_conf"

    # Update server_name with actual domain
    sed -i "s/server_name yourdomain\.com www\.yourdomain\.com;/server_name $domain www.$domain;/" "$nginx_conf"

    log_success "Nginx configuration updated"
    log_info "Backup saved to: $nginx_conf.backup"
}

# Update .env.production file
update_env_file() {
    local project_dir=$1
    local domain=$2

    log_info "Updating .env.production with HTTPS URL..."

    local env_file="$project_dir/.env.production"

    if [[ ! -f "$env_file" ]]; then
        log_warning ".env.production not found at $env_file"
        return 1
    fi

    # Update NEXT_PUBLIC_SITE_URL to https
    sed -i "s|^NEXT_PUBLIC_SITE_URL=.*|NEXT_PUBLIC_SITE_URL=https://$domain|" "$env_file"

    log_success ".env.production updated with HTTPS URL"
}

# Create auto-renewal script
setup_auto_renewal() {
    local domain=$1
    local project_dir=$2
    local project_user=$3

    log_info "Setting up automatic certificate renewal..."

    local renewal_script="/opt/renew-ssl-$domain.sh"

    cat > "$renewal_script" <<EOF
#!/bin/bash
set -e

DOMAIN="$domain"
PROJECT_DIR="$project_dir"
PROJECT_USER="$project_user"

# Stop nginx to free port 80
cd "\$PROJECT_DIR"
if [[ -f "docker-compose.prod.yml" ]]; then
    docker compose -f docker-compose.prod.yml stop nginx 2>/dev/null || docker-compose -f docker-compose.prod.yml stop nginx
elif [[ -f "docker-compose.yml" ]]; then
    docker compose stop nginx 2>/dev/null || docker-compose stop nginx
fi

# Renew certificate
certbot renew --standalone --quiet

# Copy renewed certificates
cp "/etc/letsencrypt/live/\$DOMAIN/fullchain.pem" "\$PROJECT_DIR/ssl/cert.pem"
cp "/etc/letsencrypt/live/\$DOMAIN/privkey.pem" "\$PROJECT_DIR/ssl/key.pem"
chown -R "\$PROJECT_USER:\$PROJECT_USER" "\$PROJECT_DIR/ssl"
chmod 644 "\$PROJECT_DIR/ssl/cert.pem"
chmod 600 "\$PROJECT_DIR/ssl/key.pem"

# Restart services
if [[ -f "docker-compose.prod.yml" ]]; then
    docker compose -f docker-compose.prod.yml up -d 2>/dev/null || docker-compose -f docker-compose.prod.yml up -d
elif [[ -f "docker-compose.yml" ]]; then
    docker compose up -d 2>/dev/null || docker-compose up -d
fi

echo "[\$(date)] SSL certificate renewed successfully" >> /var/log/ssl-renewal.log
EOF

    chmod +x "$renewal_script"

    # Add to crontab (run daily at 3 AM)
    (crontab -l 2>/dev/null | grep -v "$renewal_script" || true; echo "0 3 * * * $renewal_script >> /var/log/ssl-renewal.log 2>&1") | crontab -

    log_success "Auto-renewal configured (runs daily at 3 AM)"
    log_info "Renewal script: $renewal_script"
}

# Main setup function
main() {
    print_header

    check_root

    # Get parameters or prompt
    DOMAIN="${1:-}"
    PROJECT_DIR="${2:-}"
    PROJECT_USER="${3:-}"
    EMAIL="${4:-}"
    INCLUDE_WWW="${5:-no}"

    # Prompt for missing parameters
    if [[ -z "$DOMAIN" ]]; then
        echo -e "${CYAN}Enter your domain name (e.g., example.com):${NC}"
        read -r DOMAIN
    fi

    if ! validate_domain "$DOMAIN"; then
        exit 1
    fi

    if [[ -z "$PROJECT_DIR" ]]; then
        echo -e "${CYAN}Enter project directory path (e.g., /opt/myapp):${NC}"
        read -r PROJECT_DIR
    fi

    if [[ ! -d "$PROJECT_DIR" ]]; then
        log_error "Project directory does not exist: $PROJECT_DIR"
        exit 1
    fi

    if [[ -z "$PROJECT_USER" ]]; then
        echo -e "${CYAN}Enter project user (e.g., appuser):${NC}"
        read -r PROJECT_USER
    fi

    if ! id "$PROJECT_USER" &>/dev/null; then
        log_error "User does not exist: $PROJECT_USER"
        exit 1
    fi

    if [[ -z "$EMAIL" ]]; then
        echo -e "${CYAN}Enter your email for certificate notifications:${NC}"
        read -r EMAIL
    fi

    if ! validate_email "$EMAIL"; then
        exit 1
    fi

    if [[ "$INCLUDE_WWW" != "yes" && "$INCLUDE_WWW" != "no" ]]; then
        echo -e "${CYAN}Include www.$DOMAIN? (y/N):${NC}"
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            INCLUDE_WWW="yes"
        else
            INCLUDE_WWW="no"
        fi
    fi

    # Get server IPs
    SERVER_IPV4=$(curl -4 -s ifconfig.me 2>/dev/null || echo "")
    SERVER_IPV6=$(curl -6 -s ifconfig.me 2>/dev/null || echo "")

    echo ""
    log_info "Configuration:"
    echo "  Domain: $DOMAIN"
    if [[ "$INCLUDE_WWW" == "yes" ]]; then
        echo "  Also: www.$DOMAIN"
    fi
    echo "  Project: $PROJECT_DIR"
    echo "  User: $PROJECT_USER"
    echo "  Email: $EMAIL"
    echo "  Server IPv4: ${SERVER_IPV4:-Not available}"
    echo "  Server IPv6: ${SERVER_IPV6:-Not available}"
    echo ""

    # Check DNS
    print_section "Checking DNS Configuration"
    if ! check_dns "$DOMAIN" ""; then
        log_error "DNS check failed."
        echo ""
        log_info "To fix this issue:"
        echo "  1. Go to your domain registrar's DNS settings"
        echo "  2. Add/Update A record (IPv4):"
        [[ -n "$SERVER_IPV4" ]] && echo "     Type: A, Name: @, Value: $SERVER_IPV4"
        echo "  3. Optionally add AAAA record (IPv6):"
        [[ -n "$SERVER_IPV6" ]] && echo "     Type: AAAA, Name: @, Value: $SERVER_IPV6"
        echo "  4. Wait 5-10 minutes for DNS propagation"
        echo "  5. Run this script again"
        echo ""
        exit 1
    fi

    # Confirm before proceeding
    echo ""
    log_warning "This will:"
    echo "  1. Install Certbot (if needed)"
    echo "  2. Stop nginx temporarily"
    echo "  3. Obtain SSL certificate from Let's Encrypt"
    echo "  4. Update nginx configuration"
    echo "  5. Update .env.production"
    echo "  6. Set up auto-renewal"
    echo ""
    echo -e "${CYAN}Continue? (y/N):${NC}"
    read -r response

    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        log_info "Setup cancelled"
        exit 0
    fi

    # Install certbot
    print_section "Installing Certbot"
    install_certbot

    # Stop services
    print_section "Preparing for Certificate Issuance"
    stop_services "$PROJECT_DIR"

    # Obtain certificate
    print_section "Obtaining SSL Certificate"
    if ! obtain_certificate "$DOMAIN" "$EMAIL" "$INCLUDE_WWW"; then
        log_error "Certificate issuance failed"
        log_info "Restoring services without SSL configuration"
        start_services "$PROJECT_DIR"
        echo ""
        log_warning "Common reasons for failure:"
        echo "  • Port 80 is blocked by firewall"
        echo "  • Another service is using port 80"
        echo "  • Rate limit reached (5 failures per hour)"
        echo "  • Domain not yet propagated to DNS servers"
        echo ""
        log_info "Check certbot logs:"
        echo "  sudo tail -50 /var/log/letsencrypt/letsencrypt.log"
        echo ""
        exit 1
    fi

    # Copy certificates
    print_section "Installing Certificates"
    if ! copy_certificates "$DOMAIN" "$PROJECT_DIR" "$PROJECT_USER"; then
        log_error "Failed to copy certificates"
        start_services "$PROJECT_DIR"
        exit 1
    fi

    # Update nginx config (only after certificates are successfully copied)
    print_section "Configuring HTTPS"
    if ! update_nginx_config "$PROJECT_DIR" "$DOMAIN"; then
        log_warning "Failed to update nginx config automatically"
        log_info "You may need to update it manually"
    fi

    # Update env file
    if ! update_env_file "$PROJECT_DIR" "$DOMAIN"; then
        log_warning "Failed to update .env.production automatically"
        log_info "You may need to update it manually"
    fi

    # Setup auto-renewal
    print_section "Setting Up Auto-Renewal"
    setup_auto_renewal "$DOMAIN" "$PROJECT_DIR" "$PROJECT_USER"

    # Start services
    print_section "Starting Services"
    start_services "$PROJECT_DIR"

    # Final message
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}              SSL/HTTPS SETUP COMPLETE!${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    log_success "Your site is now accessible at:"
    echo "  • https://$DOMAIN"
    if [[ "$INCLUDE_WWW" == "yes" ]]; then
        echo "  • https://www.$DOMAIN"
    fi
    echo ""
    log_info "Certificate will auto-renew every 60 days"
    log_info "HTTP traffic will automatically redirect to HTTPS"
    echo ""
    log_info "To verify SSL is working:"
    echo "  curl -I https://$DOMAIN"
    echo ""
    log_info "To check certificate status:"
    echo "  sudo certbot certificates"
    echo ""
}

# Run main function
main "$@"
