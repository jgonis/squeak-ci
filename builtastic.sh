#! /bin/sh

SRC=$(cd $(dirname "$0"); pwd)
. "${SRC}/versions.sh"
. "${SRC}/functions.sh"

# : ${WORKSPACE:=`pwd`} # Default to the current directory to ease testing
TEST_IMAGE_NAME="Squeak4.4-trunk"
IMAGE_NAME="TrunkImage"
RUN_TEST_IMAGE_NAME="PostTestTrunkImage"

build_cog_vm "linux"
build_interpreter_vm "linux"
prepare_target ${SRC} $TEST_IMAGE_NAME $IMAGE_NAME

# Update the image, and record the update number in target/TrunkImage.version
echo Updating target image...
update_image ${SRC} ${COG_VM}
ensure_interpreter_compatible_image ${SRC} ${IMAGE_NAME}

# Copy the clean image so we can run the tests without touching the artifact.
cp "${SRC}/target/$IMAGE_NAME.image" "${SRC}/target/$RUN_TEST_IMAGE_NAME.image"
cp "${SRC}/target/$IMAGE_NAME.changes" "${SRC}/target/$RUN_TEST_IMAGE_NAME.changes"

# Run the tests and snapshot the image post-test.
echo Running tests on VM ${COG_VM}...
$COG_VM -vm-sound-null -vm-display-null "${SRC}/target/$RUN_TEST_IMAGE_NAME.image" "${SRC}/tests.st"
