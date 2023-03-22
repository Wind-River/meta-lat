# Prompt for the installation target device, without wait (ignore option --timeout)
#lat-disk --install-device=ask

# Set /dev/sda as default installation target, without prompt
#lat-disk --install-device=/dev/sda --timeout=0

# Try to install a list of available devices
# /dev/nvme0n1,/dev/mmcblk0,/dev/sda,/dev/vda
# It is useful while install device is not clear
# The fat size is 32MB, boot size is 512MB, root size is 8096MB,
# the rest free disk space is expanded to /var,
# wait 10 seconds before erasing disk
lat-disk --install-device=/dev/nvme0n1,/dev/mmcblk0,/dev/sda,/dev/vda --fat-size=32 --boot-size=512 --root-size=8096 --var-size=0 --timeout=10
