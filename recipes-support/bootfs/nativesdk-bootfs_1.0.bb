include bootfs.inc

DESCRIPTION = "Provide a nativesdk command will build a small boot image \
which can be used for deployment with OSTree"

RDEPENDS:${PN} += " \
    nativesdk-bash \
    nativesdk-perl \
    nativesdk-ostree \
    nativesdk-wic \
"

inherit nativesdk
