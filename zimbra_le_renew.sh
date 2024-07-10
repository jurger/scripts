#!/bin/bash
DOMAIN="mail.example.com"
certbot renew --force-renewal --standalone
cp /etc/letsencrypt/live/$DOMAIN/* /opt/zimbra/ssl/zimbra/commercial/
chown zimbra /opt/zimbra/ssl/zimbra/commercial/*
cd /opt/zimbra/ssl/zimbra/commercial
wget https://letsencrypt.org/certs/isrgrootx1.pem.txt
wget https://letsencrypt.org/certs/letsencryptauthorityx3.pem.txt
echo "-----BEGIN CERTIFICATE-----" > new_chain.pem
openssl x509 -in chain.pem -outform der | base64 -w 64 >> new_chain.pem
echo "-----END CERTIFICATE-----" >> new_chain.pem
mv new_chain.pem chain.pem
cat isrgrootx1.pem.txt >> chain.pem
cat letsencryptauthorityx3.pem.txt >> chain.pem
su - zimbra -c "zmcertmgr verifycrt comm /opt/zimbra/ssl/zimbra/commercial/privkey.pem /opt/zimbra/ssl/zimbra/commercial/cert.pem /opt/zimbra/ssl/zimbra/commercial/chain.pem"
mv privkey.pem commercial.key
su - zimbra -c "zmcertmgr deploycrt comm /opt/zimbra/ssl/zimbra/commercial/cert.pem /opt/zimbra/ssl/zimbra/commercial/chain.pem"
su - zimbra -c "zmcontrol restart"
