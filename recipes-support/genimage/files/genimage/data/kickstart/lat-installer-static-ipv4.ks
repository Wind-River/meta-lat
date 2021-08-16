# Static IPV4 only
network --bootproto=static --device=eth0  --ip=192.168.7.2 --netmask=255.255.255.0 --gateway=192.168.7.1


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

