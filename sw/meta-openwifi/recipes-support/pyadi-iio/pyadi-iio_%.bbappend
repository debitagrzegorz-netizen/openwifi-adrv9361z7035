# meta-adi builds pyadi-iio from main with AUTOREV. Pin the revision from
# config/versions.conf (build.sh writes PYADI_IIO_REV into petalinuxbsp.conf).
SRCREV = "${PYADI_IIO_REV}"
