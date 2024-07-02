#!/bin/bash
echo 17179869184>> /sys/module/zfs/parameters/zfs_arc_min
echo 34359738368>> /sys/module/zfs/parameters/zfs_arc_max
echo "options zfs zfs_arc_max=34359738368" >> /etc/modprobe.d/zfs.conf
echo "options zfs zfs_arc_min=17179869184" >> /etc/modprobe.d/zfs.conf
update-initramfs -u
