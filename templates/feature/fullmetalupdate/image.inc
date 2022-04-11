IMAGE_ROOTFS_EXTRA_SPACE = "2097152"

IMAGE_CLASSES:append = " ${@'fullmetalupdate_package_preinstalled_ostree' if not oe.types.boolean(d.getVar('IMAGE_ENABLE_CONTAINER')) else ''}"
IMAGE_CLASSES:append = " ${@'fullmetalupdate_push_image_to_ostree' if not oe.types.boolean(d.getVar('IMAGE_ENABLE_CONTAINER')) else ''}"

IMAGE_INSTALL +=  " fullmetalupdate"
IMAGE_INSTALL +=  " runc-docker"
