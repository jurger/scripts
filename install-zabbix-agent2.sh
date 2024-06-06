#!/bin/bash
function get_os() 
   {
        local distro
        local version

        if [ `uname -s` = 'Linux' ] && [ -e '/etc/debian_version' ]; then
            if [ -e '/etc/lsb-release' ]; then
                # Mostly Ubuntu, but also Debian can have it too.
                . /etc/lsb-release
                distro="$DISTRIB_ID"
                version="$DISTRIB_RELEASE"
            else
                distro="Debian"
                version=`head -n 1 /etc/debian_version`
                version=`echo $version | grep -o "^[0-9]\+"`
            fi
        else
            echo 'false'
        fi

        echo ${distro}_$version
  }

function install()  
{
	case `get_os` in
            "Ubuntu_20.04")
				wget https://repo.zabbix.com/zabbix/6.0/ubuntu/pool/main/z/zabbix-release/zabbix-release_6.0-4+ubuntu20.04_all.deb
				dpkg -i zabbix-release_6.0-4+ubuntu20.04_all.deb
            ;;
            "Ubuntu_22.04")
				wget https://repo.zabbix.com/zabbix/6.0/ubuntu/pool/main/z/zabbix-release/zabbix-release_6.0-4+ubuntu22.04_all.deb
				dpkg -i zabbix-release_6.0-4+ubuntu22.04_all.deb
            ;;
            "Ubuntu_24.04")
				wget https://repo.zabbix.com/zabbix/6.0/ubuntu/pool/main/z/zabbix-release/zabbix-release_6.0-6+ubuntu24.04_all.deb
				dpkg -i zabbix-release_6.0-6+ubuntu24.04_all.deb
                ;;
			"Debian_11")
				wget https://repo.zabbix.com/zabbix/6.0/debian/pool/main/z/zabbix-release/zabbix-release_6.0-4+debian11_all.deb
				dpkg -i zabbix-release_6.0-4+debian11_all.deb
			;;
			"Debian_12")
				wget https://repo.zabbix.com/zabbix/6.0/debian/pool/main/z/zabbix-release/zabbix-release_6.0-5+debian12_all.deb
				dpkg -i zabbix-release_6.0-5+debian12_all.deb
			;;
			*)
				echo "Unsupported OS"
				exit 1
			;;
    esac

	apt update
	apt -y install zabbix-agent2 zabbix-agent2-plugin-*

}

install

sed -i 's/Server=127.0.0.1/Server=opns.fortlab.net/' /etc/zabbix/zabbix_agent2.conf
sed -i 's/ServerActive=127.0.0.1/ServerActive=opns.fortlab.net/' /etc/zabbix/zabbix_agent2.conf
systemctl restart zabbix-agent2
systemctl enable zabbix-agent2

