SUMMARY = "Non-interactive ssh password auth"
DESCRIPTION = "Sshpass is a tool for non-interactivly performing password authentication with SSH's so called "interactive keyboard password authentication". Most user should use SSH's more secure public key authentiaction instead."
HOMEPAGE = "https://sourceforge.net/projects/sshpass/"
LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://COPYING;md5=94d55d512a9ba36caa9b7df079bae19f"

SRC_URI = "https://versaweb.dl.sourceforge.net/project/sshpass/sshpass/${PV}/sshpass-${PV}.tar.gz"

SRC_URI[md5sum] = "191a9128a74d81ae36744d5deb50d164"
SRC_URI[sha256sum] = "71746e5e057ffe9b00b44ac40453bf47091930cba96bbea8dc48717dedc49fb7"

inherit autotools pkgconfig

BBCLASSEXTEND = "native"
