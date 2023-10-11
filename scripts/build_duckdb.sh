#!/bin/bash

set -e
set -o pipefail

DUCKDB_VERSION=${1:-"v0.9.1"}
REMOVE_SOURCE_FILES=${2:-"N"}

echo "Variable: DUCKDB_VERSION=${DUCKDB_VERSION}"

SCRIPT_DIR=$(dirname ${0})

pushd "${SCRIPT_DIR}/.."

rm -rf duckdb

echo "Cloning DuckDB."
git clone --depth 1 https://github.com/duckdb/duckdb.git --branch ${DUCKDB_VERSION} --recurse-submodules

pushd duckdb

# Do some Mac stuff if needed...
OS=$(uname)
if [ "${OS}" == "Darwin" ]; then
  echo "Running Mac-specific setup steps..."
  export MACOSX_DEPLOYMENT_TARGET=$(sw_vers -productVersion)
fi

if [ ! -d "build/release" ]; then
    echo "Building DuckDB"
    GEN=ninja make
fi
popd

# Build the python library from source
pushd duckdb/tools/pythonpkg
python setup.py install
popd

# Copy DuckDB executable and shared libraries/headers to /usr/local
pushd duckdb
cp build/release/duckdb /usr/local/bin
cp build/release/src/libduckdb* /usr/local/lib/
cp src/include/duckdb.h /usr/local/include/
cp src/include/duckdb.hpp /usr/local/include/
cp -R src/include/duckdb /usr/local/include/

# Remove git stuff
rm -rf .git

popd

# Remove source files
if [ "${REMOVE_SOURCE_FILES}" == "Y" ]; then
  echo "Removing DuckDB source files..."
  rm -rf ./duckdb
fi

popd
