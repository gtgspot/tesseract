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

if [[ ! "${TESSERACT_ENABLE_TRAINING:-}" =~ ^(1|ON|TRUE|on|true)$ ]]; then
  cmake_args+=("-DBUILD_TRAINING_TOOLS=OFF")
fi

if [[ ! "${TESSERACT_USE_SYSTEM_FMT:-}" =~ ^(1|ON|TRUE|on|true)$ ]]; then
  export CXXFLAGS="${CXXFLAGS:-} -I${PWD}/src/fmt/include -DFMT_HEADER_ONLY=1"
fi

if [[ "${TESSERACT_USE_SW:-}" =~ ^(1|ON|TRUE|on|true)$ ]]; then
  cmake_args+=("-DSW_BUILD=ON")
fi

if [[ -n "${TESSERACT_EXTRA_CMAKE_ARGS:-}" ]]; then
  # shellcheck disable=SC2206
  extra_args=(${TESSERACT_EXTRA_CMAKE_ARGS})
  cmake_args+=("${extra_args[@]}")
fi

cmake "${cmake_args[@]}"
