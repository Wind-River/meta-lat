#!/bin/bash
#
# Copyright (c) 2022 Wind River Systems, Inc.
#
# SPDX-License-Identifier:  GPL-2.0-only
#
set -x
set -e
## Require environments
# DEPLOY_DIR_IMAGE
# IMAGE_NAME
# DATETIME
# MACHINE
atf_s32="${DEPLOY_DIR_IMAGE}/atf-aptiv_cvc_sousa.s32"
wicimage="$DEPLOY_DIR_IMAGE/${IMAGE_NAME}-${MACHINE}-${DATETIME}.rootfs.wic"
dd if=$atf_s32 of=$wicimage conv=notrunc bs=256 count=1 seek=0
dd if=$atf_s32 of=$wicimage conv=notrunc bs=512 seek=1 skip=1
