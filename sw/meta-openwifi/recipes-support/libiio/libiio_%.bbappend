# meta-adi builds libiio-v0 with AUTOREV. Pin the revision from
# config/versions.conf (build.sh writes LIBIIO_REV into petalinuxbsp.conf).
SRCREV = "${LIBIIO_REV}"
