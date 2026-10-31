# meta-adi uses AUTOREV. Current libad9361 main includes <iio/iio.h> and
# calls iio_attr_* helpers that this image's libiio does not provide.
# Pin the offline revision from the recipe, which includes <iio.h>.
SRCREV = "2264074505ad4911155c815104292c6fbf98f62c"

# That revision still adds the test tree, whose files include <iio/iio.h>.
# The library itself does not. Skip the tests.
do_configure:prepend() {
    sed -i '/add_subdirectory(test)/d' ${S}/CMakeLists.txt
}
