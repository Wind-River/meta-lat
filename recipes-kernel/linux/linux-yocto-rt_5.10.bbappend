require linux-yocto-intel-x86.inc

KBRANCH_intel-x86  = "v5.10/standard/preempt-rt/x86"

LINUX_VERSION_intel-x86 ?= "5.10.x"

FILESEXTRAPATHS_prepend_intel-x86 := "${THISDIR}/files:"

SRC_URI_append_intel-x86 = " \
    file://0001-drm-i915-gt-Fix-a-lockdep-warning-with-interrupts-en.patch \
"
