#! /bin/sh

# Assume that something's copied the source tarball to this directory.

SRC=$(cd $(dirname "$0"); pwd)
. "${SRC}/versions.sh"
. "${SRC}/functions.sh"

mkdir -p "${SRC}/target"
curl -o "${SRC}/target/archive.zip" http://squeakci.org/job/InterpreterVM/lastSuccessfulBuild/artifact/*zip*/archive.zip
pushd "${SRC}/target/"
unzip -o archive.zip
mv archive/* .
TARBALL=`find . -name Squeak-vm-unix-*-src*.tar.gz | grep -v Cog | head -1`
tar zxvf ${TARBALL}
SOURCE=`find . -name Squeak-vm-unix-*-src | grep -v Cog | head -1`
(cd $SOURCE/platforms/unix; make)