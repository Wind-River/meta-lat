COMPATIBLE_MACHINE:intel-x86-64 = "intel-x86-64"

#add the depends of cdrtools-native to make sure it is
#always built to support the usb-image & iso-image UEFI
#booting by default  without explicitly add the configure
#option of "--enable-bootimage=iso"

DEPENDS:append:intel-x86-64 = " cdrtools-native"

# A method to install/update for bzImage on a deployed target
KERNELLOADEREXTENSION:append:intel-x86-64 = " kernel-grub"

TARGET_SUPPORTED_KTYPES:intel-x86 = "standard preempt-rt"

do_install:append:intel-x86() {
	rm -rf ${D}/lib/modules/${KERNEL_VERSION}/kernel/drivers/crypto
}

KERNEL_VERSION_SANITY_SKIP = "1"
SRCREV_machine:intel-x86 ?= "${AUTOREV}"
SRCREV_meta:intel-x86 ?= "${AUTOREV}"
