# Similar to meta/conf/machine/include/qemu.inc but influences the
# distro content (in particular the kernel) less than qemu.inc.

# Ensure that qemu gets built when building images.
EXTRA_IMAGEDEPENDS += "qemu-native qemu-helper-native"

# Build ovmf firmware for uefi support in qemu.
EXTRA_IMAGEDEPENDS += "ovmf"
