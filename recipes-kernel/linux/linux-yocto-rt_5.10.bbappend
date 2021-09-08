require linux-yocto-intel-x86.inc

KBRANCH:intel-x86  = "v5.10/standard/preempt-rt/x86"

LINUX_VERSION:intel-x86 ?= "5.10.x"

FILESEXTRAPATHS:prepend:intel-x86 := "${THISDIR}/files:"

SRC_URI:append:intel-x86 = " \
    file://0001-drm-i915-gt-Fix-a-lockdep-warning-with-interrupts-en.patch \
"
