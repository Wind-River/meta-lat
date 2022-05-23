require ${@bb.utils.contains('DISTRO_FEATURES', 'ostree', '${BPN}_lat.inc', '', d)}
