#!/bin/bash
systemctl stop NetworkManager
systemctl disable NetworkManager
systemctl mask NetworkManager
systemctl unmask systemd-networkd.service
systemctl enable systemd-networkd.service
systemctl start systemd-networkd.service
