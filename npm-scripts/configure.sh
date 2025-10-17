#!/usr/bin/env bash

set -euo pipefail

BUILD_DIR=${BUILD_DIR:-build}
INSTALL_SUBDIR=${INSTALL_SUBDIR:-${BUILD_DIR}/install}
CMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE:-Release}

cmake_args=(
  "-S" "."
  "-B" "${BUILD_DIR}"
  "-DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}"
  "-DCMAKE_INSTALL_PREFIX=${PWD}/${INSTALL_SUBDIR}"
)

if [[ "${TESSERACT_USE_SW:-}" =~ ^(1|ON|TRUE|on|true)$ ]]; then
  cmake_args+=("-DSW_BUILD=ON")
fi

if [[ "${TESSERACT_ENABLE_TRAINING:-ON}" =~ ^(0|OFF|FALSE|off|false)$ ]]; then
  cmake_args+=("-DBUILD_TRAINING_TOOLS=OFF")
else
  cmake_args+=("-DBUILD_TRAINING_TOOLS=ON")
fi

if [[ "${TESSERACT_BUILD_TESTS:-ON}" =~ ^(0|OFF|FALSE|off|false)$ ]]; then
  cmake_args+=("-DBUILD_TESTS=OFF")
else
  cmake_args+=("-DBUILD_TESTS=ON")
fi

if [[ "${TESSERACT_OPENMP:-ON}" =~ ^(0|OFF|FALSE|off|false)$ ]]; then
  cmake_args+=("-DOPENMP_BUILD=OFF")
else
  cmake_args+=("-DOPENMP_BUILD=ON")
fi

# Always try to build with libarchive if the dependency is available. This matches
# the request to provide compressed model file support during deployments.
if [[ "${TESSERACT_DISABLE_ARCHIVE:-}" =~ ^(1|ON|TRUE|on|true)$ ]]; then
  cmake_args+=("-DDISABLE_ARCHIVE=ON")
else
  cmake_args+=("-DDISABLE_ARCHIVE=OFF")
fi

# Prefer the system fmt installation when available to keep feature parity with
# make_args_checked support in the bundled sources while still allowing a
# header-only fallback for environments without the package installed.
if [[ ! "${TESSERACT_USE_SYSTEM_FMT:-}" =~ ^(1|ON|TRUE|on|true)$ ]]; then
  export CXXFLAGS="${CXXFLAGS:-} -I${PWD}/src/fmt/include -DFMT_HEADER_ONLY=1"
fi

if [[ -n "${TESSERACT_EXTRA_CMAKE_ARGS:-}" ]]; then
  # shellcheck disable=SC2206
  extra_args=(${TESSERACT_EXTRA_CMAKE_ARGS})
  cmake_args+=("${extra_args[@]}")
fi

cmake "${cmake_args[@]}"
