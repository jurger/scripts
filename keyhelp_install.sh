wget https://install.keyhelp.de/get_keyhelp.php -O install_keyhelp.sh

bash install_keyhelp.sh \
  --non-interactive \
  --hostname-fqdn=panel.example.com \
  --admin-username=admin \
  --admin-password='StrongPassword' \
  --admin-email=admin@example.com \
  --notification=admin@example.com
