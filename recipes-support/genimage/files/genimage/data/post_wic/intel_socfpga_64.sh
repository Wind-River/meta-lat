#!/bin/bash
#
# Copyright (c) 2023 Wind River Systems, Inc.
#
# SPDX-License-Identifier:  GPL-2.0
#
set -x
set -e
## Require environments
# DEPLOY_DIR_IMAGE
# IMAGE_NAME
# DATETIME
# MACHINE

# Create Stratix10 and Agilex wic image separately
for config in stratix10 agilex; do
        cd "${DEPLOY_DIR_IMAGE}"

        for file_name in u-boot.img u-boot-dtb.img u-boot.itb; do
                if [ -e ${file_name} ]; then
                        rm -rf ${file_name}
                fi
                if [ "$file_name" = "u-boot.itb" ];then
                        ln -sf u-boot-${config}-socdk-mmc.itb ${file_name}
                elif [ "$file_name" = "u-boot-dtb.img" ];then
                        ln -sf u-boot-dtb-${config}-socdk-mmc.img ${file_name}
                else
                        ln -sf u-boot-${config}-socdk-mmc.img ${file_name}
                fi
        done

        cp ${DEPLOY_DIR_IMAGE}/${IMAGE_NAME}-${MACHINE}.wic ${DEPLOY_DIR_IMAGE}/${IMAGE_NAME}-${MACHINE}-${config}.wic

        for file_name in u-boot.img u-boot-dtb.img u-boot.itb; do
                wic cp ${file_name} ${DEPLOY_DIR_IMAGE}/${IMAGE_NAME}-${MACHINE}-${config}.wic:1/
        done

        cd "${DEPLOY_DIR_IMAGE}"
        bmaptool create "${IMAGE_NAME}-${MACHINE}-${config}.wic" -o "${IMAGE_NAME}-${MACHINE}-${config}.wic.bmap"
done

# Remove the default wic file
rm -rf "${DEPLOY_DIR_IMAGE}/${IMAGE_NAME}-${MACHINE}.wic"
rm -rf "${DEPLOY_DIR_IMAGE}/${IMAGE_NAME}-${MACHINE}.wic.bmap"
rm -rf "${DEPLOY_DIR_IMAGE}/${IMAGE_NAME}-${MACHINE}-${DATETIME}.wic"
rm -rf "${DEPLOY_DIR_IMAGE}/${IMAGE_NAME}-${MACHINE}-${DATETIME}.wic.bmap"

