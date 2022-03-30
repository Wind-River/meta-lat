SUMMARY = "Tool that push ostree commits over ssh"
DESCRIPTION = "Tool that push ostree commits over ssh"
HOMEPAGE = "https://github.com/FullMetalUpdate/ostree-push"
LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://COPYING;md5=b234ee4d69f5fce4486a80fdaf4a4263"

SRC_URI = "git://github.com/FullMetalUpdate/ostree-push.git;branch=master;protocol=https \
           file://0001-fix-shebang-of-ostree-push.patch \
           file://0001-ostree-push-support-pass-extra-ssh-option.patch \
"

S="${WORKDIR}/git"

SRCREV="dd4a282856743f58cdeb531d07825fc21cad43aa"

do_install () {
    oe_runmake install DESTDIR=${D} PREFIX=${prefix}
}

BBCLASSEXTEND = "native"

