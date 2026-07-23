#!/bin/bash

wget https://install.keyhelp.de/get_keyhelp.php -O install_keyhelp.sh
CURRENT_FQDN=$(hostname -f 2>/dev/null)
# Check if FQDN is non-empty and contains at least one dot
if [ -z "$CURRENT_FQDN" ] || [[ "$CURRENT_FQDN" != *.* ]]; then
  echo "ERROR: Valid FQDN is not configured (current value: '$CURRENT_FQDN')."
  echo "Set a valid hostname first: hostnamectl set-hostname panel.yourdomain.com"
  exit 1
fi
echo "SUCCESS: FQDN verified -> $CURRENT_FQDN"

# Interactive password prompt (visible input)
read -rp "Enter KeyHelp admin password: " ADMIN_PASSWORD

if [ -z "$ADMIN_PASSWORD" ]; then
  echo "ERROR: Password cannot be empty."
  exit 1
fi


bash install_keyhelp.sh \
  --non-interactive \
  --hostname-fqdn="$CURRENT_FQDN" \
  --admin-username=keyadmin \
  --admin-password="$ADMIN_PASSWORD" \
  --admin-email=root@sayob.com \

