# DHCP IPV4 with IPV6 auto, reactivate at installation time and enable at boot time
network  --bootproto=dhcp --device=eth0 --ipv6=auto --activate

# DHCP IPV4 with IPV6 auto, not enable at boot time
network  --bootproto=dhcp --device=eth1 --onboot=off --ipv6=auto

# Hostname
network  --hostname=localhost

# Static IPV6 only
network  --bootproto=static --device=eth2 --noipv4 --ipv6=fd01:100::a/64 --activate --ipv6gateway=fd01:100::1

lat-disk --install-device=/dev/sda --fat-size=32 --boot-size=512 --root-size=8096 --var-size=0

%pre --interpreter=/bin/sh
echo "Pre script: Create partition on disk for /opt"
set -x
# Chose disk
dev="/dev/sdb"

# Deletie all the partitions from a hard disk
sgdisk -Z $dev

# The sector number of the start of the largest available block of sectors on the disk
first=$(sgdisk -F $dev 2>/dev/null |grep -v Creating)

# The sector number of the end of the largest available block of sectors on the disk
end=$(sgdisk -E $dev 2>/dev/null |grep -v Creating)

# Create one partition on $dev, starting at $first and ending at $end:
sgdisk -p -n 1:$first:$end $dev

# Create an ext4 filesystem on ${dev}1
mkfs.ext4 -F -L opt ${dev}1
%end

%pre
echo "Pre script 2"
%end

%pre --interpreter=/bin/bash
echo "Pre script 3"
%end

%post
echo "Post script: Mount partition to /opt in /etc/fstab"
set -x
# Mount disk to /opt in /etc/fstab
echo "LABEL=opt /opt    auto   defaults 0 0" >> /etc/fstab
%end

%post --interpreter=/bin/bash
echo "Post script 2"
%end

%post --interpreter=/bin/bash --nochroot
echo "Post script 3, root dir is ${IMAGE_ROOTFS}"
%end

