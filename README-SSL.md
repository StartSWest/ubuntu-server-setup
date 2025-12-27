# SSL/HTTPS Setup

To enable HTTPS for this project, use the SSL setup script from the `ubuntu-server-setup` repository.

## Quick Setup

```bash
# On your server, run:
wget https://raw.githubusercontent.com/StartSWest/ubuntu-server-setup/main/setup-ssl.sh
chmod +x setup-ssl.sh
sudo bash setup-ssl.sh
```

The script will ask for:
- **Domain name**: `raw-materials.ivancosoftware.com`
- **Project directory**: `/opt/raw_materials`
- **Project user**: `rmuser`
- **Email**: Your email for certificate notifications
- **Include www**: Whether to include www subdomain

## What It Does

1. ✅ Verifies DNS points to your server
2. ✅ Installs Certbot (Let's Encrypt client)
3. ✅ Obtains FREE SSL certificate
4. ✅ Updates nginx configuration for HTTPS
5. ✅ Updates `.env.production` to use HTTPS URL
6. ✅ Sets up automatic certificate renewal

## Requirements

Before running the script:

1. **Domain must point to server**
   - Add A record in DNS: `raw-materials.ivancosoftware.com` → `your-server-ip`
   - Wait 5-10 minutes for DNS propagation

2. **Application must be running**
   - The script will temporarily stop nginx to obtain the certificate

## After SSL Setup

Your site will be accessible at:
- `https://raw-materials.ivancosoftware.com` (secure)
- `http://raw-materials.ivancosoftware.com` → Automatically redirects to HTTPS

Admin login will work properly with secure cookies over HTTPS.

## Certificate Renewal

Certificates are valid for 90 days and will auto-renew:
- Renewal script runs daily at 3 AM
- Certificates renew at 30 days before expiration
- No manual intervention needed

## Manual Certificate Check

```bash
# Check certificate status
sudo certbot certificates

# Test renewal process
sudo certbot renew --dry-run

# Force renewal (if needed)
sudo certbot renew --force-renewal
```

## See Also

- [SSL-SETUP-GUIDE.md](SSL-SETUP-GUIDE.md) - Detailed SSL setup guide
- [ubuntu-server-setup repo](https://github.com/StartSWest/ubuntu-server-setup) - Server setup scripts
