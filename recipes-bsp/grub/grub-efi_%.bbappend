#
# Copyright (C) 2016-2017, 2019  Wind River Systems, Inc.
#

require ${@bb.utils.contains('DISTRO_FEATURES', 'ostree', '${BPN}_ostree.inc', '', d)}
