#!/bin/bash

if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VERSION_ID=$VERSION_ID
    else
        echo "Unsupported OS. Exiting."
        exit 1
fi

wget https://repo.zabbix.com/zabbix/6.0/${OS}/pool/main/z/zabbix-release/zabbix-release_6.0-5+${OS}${VERSION_ID}_all.deb
dpkg -i zabbix-release_6.0-5+${OS}${VERSION_ID}_all.deb
apt update
apt install -y zabbix-agent2 zabbix-agent2-plugin-*

#read -p "Enter IP-address or domain name of zabbix server: " -e ZBX_SERVER
#sed -i 's/Server=127.0.0.1/Server=$ZBX_SERVER/' /etc/zabbix/zabbix_agent2.conf
#sed -i 's/ServerActive=127.0.0.1/ServerActive=$ZBX_SERVER/' /etc/zabbix/zabbix_agent2.conf
sed -i 's/Server=127.0.0.1/Server=opns.fortlab.net/' /etc/zabbix/zabbix_agent2.conf
sed -i 's/ServerActive=127.0.0.1/ServerActive=opns.fortlab.net/' /etc/zabbix/zabbix_agent2.conf

systemctl restart zabbix-agent2
systemctl enable zabbix-agent2
systemctl restart zabbix-agent2
systemctl enable zabbix-agent2

