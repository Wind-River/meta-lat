#
# Copyright (C) 2022  Wind River Systems, Inc.
#

require ${@bb.utils.contains('DISTRO_FEATURES', 'ostree', '${BPN}_ostree.inc', '', d)}
