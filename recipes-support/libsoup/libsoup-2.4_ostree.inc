FILESEXTRAPATHS:prepend := "${THISDIR}/file:"

SRC_URI += "file://0001-add-soup_uri_to_string_with_password.patch \
"

CFLAGS:class-native += "-std=gnu89"
