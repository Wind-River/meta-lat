COMPATIBLE_MACHINE:intel-x86-64 = "intel-x86-64"
SRCREV_machine = "${AUTOREV}"
SRCREV_meta = "${AUTOREV}"

KBRANCH:pn-linux-yocto  = "v5.10/standard/x86"
KBRANCH:pn-linux-yocto-dev  = "standard/x86"
KBRANCH:pn-linux-yocto-rt  = "v5.10/standard/preempt-rt/x86"

KERNEL_VERSION_SANITY_SKIP = "1"
LINUX_VERSION ?= "5.10.x"

