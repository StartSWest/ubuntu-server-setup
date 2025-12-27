# Ubuntu Server Setup Scripts

Production-ready Ubuntu server setup scripts for deploying multiple projects on a single server.

## Overview

This repository contains two scripts that work together to set up an Ubuntu server for production deployments:

1. **setup-server.sh** - One-time server configuration (system-level)
2. **setup-project.sh** - Per-project setup (can be run multiple times for different projects)

## Features

### Server Setup (setup-server.sh)
- System updates and security hardening
- Docker and Docker Compose installation
- Nginx installation (system-level)
- UFW firewall configuration (ports 22, 80, 443)
- Fail2ban for intrusion prevention
- **Interactive SSH key setup for root access**
- **Optional SSH hardening with proper warnings** (password auth disabled)
- Swap file creation
- System limits optimization
- Log rotation configuration
- Optional monitoring tools (netdata, htop, iotop)
- Automatic security updates

### Project Setup (setup-project.sh)
- Project-specific user creation
- **Optional** SSH key generation (only if needed)
- Support for both **public** (HTTPS) and **private** (SSH) repositories
- Interactive GitHub key configuration with pause-and-wait
- Repository cloning with multiple options
- Project directory setup (/opt/project-name)
- Environment file initialization
- Fully generic - no hardcoded values

## Quick Start

### Step 1: Server Setup (Run Once)

On your Ubuntu server, run the server setup script as root:

```bash
# Download the server setup script
wget https://raw.githubusercontent.com/StartSWest/ubuntu-server-setup/main/setup-server.sh

# Make it executable
chmod +x setup-server.sh

# Run as root
sudo bash setup-server.sh
```

This will:
- Configure the server with security best practices
- Install Docker, Nginx, and essential tools
- Set up firewall and fail2ban
- **Guide you through SSH key setup for root access**
- **Ask before hardening SSH (prevents lockout)**
- Configure system limits and monitoring

**Important**: The script will ask you to set up SSH keys BEFORE disabling password authentication. Make sure to test SSH key login in a separate terminal before proceeding with SSH hardening.

### Step 2: Project Setup (Run Per Project)

After server setup is complete, set up your first project:

```bash
# Download the project setup script
wget https://raw.githubusercontent.com/StartSWest/ubuntu-server-setup/main/setup-project.sh

# Make it executable
chmod +x setup-project.sh

# Run as root
sudo bash setup-project.sh
```

The script will ask you for:
- Project name (e.g., "my-app", "api-service")
- Username (optional, defaults to `<project-name>-user`)
- Whether you need SSH keys (only required for private repos or pushing changes)
- Repository type (public or private)
- Repository URL or copy method

It will then:
1. Create a dedicated user for the project
2. (Optional) Generate SSH keys for GitHub access if needed
3. (Optional) Display the SSH key and pause for you to add it to GitHub
4. Clone your repository to `/opt/<project-name>`
5. Set up proper permissions and environment files

### Step 3: Deploy Your Project

After project setup, switch to your project user and deploy:

```bash
# Switch to project user
sudo -u <project-name>-user -i

# Navigate to project directory
cd /opt/<project-name>

# Run your deployment script
./scripts/deploy.sh
```

## Multiple Projects on One Server

You can run `setup-project.sh` multiple times for different projects:

```bash
# First project
sudo bash setup-project.sh
# Enter: my-app
# Creates: /opt/my-app with user my-app-user

# Second project
sudo bash setup-project.sh
# Enter: dashboard
# Creates: /opt/dashboard with user dashboard-user

# Third project
sudo bash setup-project.sh
# Enter: api-service
# Creates: /opt/api-service with user api-service-user
```

Each project gets:
- Its own Linux user
- Its own SSH keys for GitHub
- Its own directory in /opt
- Isolated environment

## Requirements

- Ubuntu 20.04 or later (tested on Ubuntu 22.04 LTS)
- Root or sudo access
- Active internet connection
- SSH access to the server

## What Gets Installed

### System Packages
- Docker and Docker Compose
- Nginx
- UFW (firewall)
- Fail2ban
- Git
- Curl, wget, htop
- Unattended upgrades
- Optional: netdata, iotop

### Security Configuration
- SSH password authentication disabled
- Root login disabled
- Fail2ban monitoring SSH, Nginx
- UFW firewall (only ports 22, 80, 443 open)
- Automatic security updates enabled

### System Optimization
- Swap file (2GB by default)
- Optimized network settings (TCP, connection limits)
- Log rotation for Docker containers
- Per-project limits (configured during project setup)

## Directory Structure

```
/opt/
├── project-name-1/          # First project
│   ├── your-app-files...
│   └── .env.production
├── project-name-2/          # Second project
│   ├── your-app-files...
│   └── .env.production
└── project-name-3/          # Third project
    ├── your-app-files...
    └── .env.production

/home/
├── project-name-1-user/     # User for first project
│   └── .ssh/
│       └── id_ed25519       # GitHub SSH key
├── project-name-2-user/     # User for second project
│   └── .ssh/
│       └── id_ed25519
└── project-name-3-user/     # User for third project
    └── .ssh/
        └── id_ed25519
```

## Customization

### Change Swap Size

Edit `setup-server.sh` and modify the `SWAP_SIZE` variable:

```bash
SWAP_SIZE="4G"  # Default is 2G
```

### Skip Monitoring Tools

When prompted during server setup, answer "N" to skip netdata installation.

### Custom Project Location

By default, projects are installed in `/opt/<project-name>`. This is configurable in `setup-project.sh`.

## Troubleshooting

### Public vs Private Repositories

**Public Repositories (No SSH needed)**:
- Use HTTPS URL: `https://github.com/username/repo.git`
- No authentication required to pull
- SSH keys only needed if you want to push changes

**Private Repositories (SSH required)**:
- Use SSH URL: `git@github.com:username/repo.git`
- SSH keys must be added to GitHub/GitLab
- Required for both pull and push operations

### SSH Key Issues

If GitHub SSH connection fails:

1. Make sure you added the SSH key to GitHub
2. Test connection manually:
   ```bash
   sudo -u <project-user> ssh -T git@github.com
   ```

### Permission Denied

If you get permission errors:

```bash
# Fix ownership
sudo chown -R <project-user>:<project-user> /opt/<project-name>

# Fix permissions
sudo chmod 755 /opt/<project-name>
```

### Firewall Blocking Ports

To open additional ports:

```bash
sudo ufw allow <port>/tcp
sudo ufw status
```

### Docker Permission Denied

If user can't run docker commands:

```bash
# Add user to docker group
sudo usermod -aG docker <project-user>

# User must log out and back in for changes to take effect
```

## Security Notes

- Root login is disabled after setup
- Make sure to set up SSH key access before restarting SSH
- All passwords authentication is disabled for SSH
- Keep your SSH private keys secure
- Regularly update the server: `sudo apt update && sudo apt upgrade`
- Monitor fail2ban logs: `sudo fail2ban-client status sshd`

## SSL/HTTPS Setup

For SSL certificates, you can use Let's Encrypt with certbot:

```bash
# Install certbot
sudo apt install certbot python3-certbot-nginx

# Get certificate (replace with your domain)
sudo certbot --nginx -d yourdomain.com -d www.yourdomain.com

# Auto-renewal is configured automatically
```

## Key Features

### ✅ Security First
- No hardcoded sensitive information
- Password authentication disabled
- Root login disabled
- Firewall configured by default
- Fail2ban intrusion prevention
- Automatic security updates

### ✅ Production Ready
- Tested on Ubuntu 22.04 LTS
- Docker and Docker Compose included
- System optimizations applied
- Monitoring tools available
- Log rotation configured

### ✅ Multi-Project Support
- Run on a single server
- Isolated users per project
- Separate SSH keys per project
- Independent deployment per project

### ✅ Flexible Repository Access
- Public repositories (HTTPS, no auth needed)
- Private repositories (SSH keys generated automatically)
- Optional SSH setup (skip if not needed)

## Privacy & Security

**This repository contains ZERO sensitive information:**
- ❌ No IP addresses
- ❌ No domain names
- ❌ No email addresses
- ❌ No usernames
- ❌ No project-specific data

All values are prompted during script execution or use dynamic variables.

## Contributing

Feel free to submit issues or pull requests to improve these scripts.

## License

MIT License - feel free to use for your own projects.

## Author

Created for deploying production projects on Ubuntu servers.

## Support

For issues or questions:
- Open an issue on GitHub
- Check the troubleshooting section above
- Review the script comments for detailed explanations
