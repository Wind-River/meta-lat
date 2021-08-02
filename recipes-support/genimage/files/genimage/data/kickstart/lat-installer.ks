# DHCP IPV4 with IPV6 auto, reactivate at installation time and enable at boot time
network  --bootproto=dhcp --device=eth0 --ipv6=auto --activate

# DHCP IPV4 with IPV6 auto, not enable at boot time
network  --bootproto=dhcp --device=eth1 --onboot=off --ipv6=auto

# Hostname
network  --hostname=localhost

# Static IPV6 only
network  --bootproto=static --device=eth2 --noipv4 --ipv6=fd01:100::a/64 --activate --ipv6gateway=fd01:100::1

# Static IPV4
network --bootproto=static --device=eth3  --ip=192.168.2.10 --netmask=255.255.255.0 --gateway=10.0.2.2 --nameserver=10.0.2.1

lat-disk --install-device=/dev/sda --fat-size=32 --boot-size=512 --root-size=8096 --var-size=0

%pre --interpreter=/bin/sh
echo "Pre script 1"
%end

%pre
echo "Pre script 2"
%end

%pre --interpreter=/bin/bash
echo "Pre script 3"
%end

%post
echo "Post script 1"
%end

%post --interpreter=/bin/bash
echo "Post script 2"
%end

%post --interpreter=/bin/bash --nochroot
echo "Post script 3, root dir is ${IMAGE_ROOTFS}"
%end

