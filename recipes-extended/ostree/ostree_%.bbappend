require ${@bb.utils.contains_any('DISTRO_FEATURES', ['ostree', 'lat'], '${BPN}_lat.inc', '', d)}

EXTRA_OECONF:append:class-native = " \
   --enable-introspection \
"

PACKAGECONFIG:append:class-native = " \ 
   libarchive \
"

