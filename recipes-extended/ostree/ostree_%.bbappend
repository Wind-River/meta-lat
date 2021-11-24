require ${@bb.utils.contains_any('DISTRO_FEATURES', ['ostree', 'lat'], '${BPN}_lat.inc', '', d)}

