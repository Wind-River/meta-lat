#
# Copyright (C) 2022 Wind River Systems, Inc.
#
FILESEXTRAPATHS:prepend := "${THISDIR}/efitools:"

SRC_URI:append = " \
    file://0001-do-not-remove-ms-uefi.esl-ms-kek.esl.patch \
"
do_compile:append() {
    # Append trusted Microsoft certs KEK and DB to LockDown.efi
    if [ ! -e append-ms ]; then
        cp -f DB.esl DB-orig.esl
        cat DB-orig.esl ms-uefi.esl > DB.esl

        cp -f KEK.esl KEK-orig.esl
        cat KEK-orig.esl ms-kek.esl > KEK.esl

        rm LockDown*efi LockDown.so LockDown.o
        base_do_compile
        touch append-ms
    fi
}
