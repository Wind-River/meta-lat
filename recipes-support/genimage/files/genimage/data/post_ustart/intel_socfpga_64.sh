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

        cp ${DEPLOY_DIR_IMAGE}/${IMAGE_NAME}-${MACHINE}.ustart.img.gz ${DEPLOY_DIR_IMAGE}/${IMAGE_NAME}-${MACHINE}-${config}.ustart.img.gz

        gunzip -f ${DEPLOY_DIR_IMAGE}/${IMAGE_NAME}-${MACHINE}-${config}.ustart.img.gz
        for file_name in u-boot.img u-boot-dtb.img u-boot.itb; do
                wic cp ${file_name} ${DEPLOY_DIR_IMAGE}/${IMAGE_NAME}-${MACHINE}-${config}.ustart.img:1/
        done

        pigz -f ${DEPLOY_DIR_IMAGE}/${IMAGE_NAME}-${MACHINE}-${config}.ustart.img
        rm -rf ${DEPLOY_DIR_IMAGE}/${IMAGE_NAME}-${MACHINE}-${config}.ustart.img

        cd "${DEPLOY_DIR_IMAGE}"
        bmaptool create "${IMAGE_NAME}-${MACHINE}-${config}.ustart.img.gz" -o "${IMAGE_NAME}-${MACHINE}-${config}.ustart.img.bmap"
done

# Remove the default wic file
rm -rf "${DEPLOY_DIR_IMAGE}/${IMAGE_NAME}-${MACHINE}.ustart.img.gz"
rm -rf "${DEPLOY_DIR_IMAGE}/${IMAGE_NAME}-${MACHINE}.ustart.img.bmap"
rm -rf "${DEPLOY_DIR_IMAGE}/${IMAGE_NAME}-${MACHINE}-${DATETIME}.ustart.img.gz"
rm -rf "${DEPLOY_DIR_IMAGE}/${IMAGE_NAME}-${MACHINE}-${DATETIME}.ustart.img.bmap"

