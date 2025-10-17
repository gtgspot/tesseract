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

normalize_bool() {
  local value="$1"
  local default="$2"

  if [[ -z "${value}" ]]; then
    value="${default}"
  fi

  case "${value}" in
    1|ON|TRUE|on|true|Yes|YES)
      printf 'ON'
      ;;
    0|OFF|FALSE|off|false|No|NO)
      printf 'OFF'
      ;;
    *)
      printf '%s' "${value}"
      ;;
  esac
}

sw_env_value=${TESSERACT_SW_BUILD:-${TESSERACT_USE_SW:-}}
if [[ -z "${sw_env_value}" ]]; then
  if command -v sw >/dev/null 2>&1; then
    cmake_args+=("-DSW_BUILD=ON")
  else
    echo "ScrollView dependency manager 'sw' not found; disabling SW_BUILD" >&2
    cmake_args+=("-DSW_BUILD=OFF")
  fi
else
  sw_requested=$(normalize_bool "${sw_env_value}" "${sw_env_value}")
  if [[ "${sw_requested}" == "OFF" ]]; then
    cmake_args+=("-DSW_BUILD=OFF")
  elif [[ "${sw_requested}" == "ON" ]]; then
    cmake_args+=("-DSW_BUILD=ON")
  else
    cmake_args+=("-DSW_BUILD=${sw_requested}")
  fi
fi

if [[ "$(normalize_bool "${TESSERACT_ENABLE_TRAINING:-}" "ON")" == "OFF" ]]; then
  cmake_args+=("-DBUILD_TRAINING_TOOLS=OFF")
else
  cmake_args+=("-DBUILD_TRAINING_TOOLS=ON")
fi

if [[ "$(normalize_bool "${TESSERACT_BUILD_TESTS:-}" "ON")" == "OFF" ]]; then
  cmake_args+=("-DBUILD_TESTS=OFF")
else
  cmake_args+=("-DBUILD_TESTS=ON")
fi

if [[ "$(normalize_bool "${TESSERACT_OPENMP:-}" "ON")" == "OFF" ]]; then
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

if [[ "$(normalize_bool "${TESSERACT_USE_SYSTEM_ICU:-}" "ON")" == "OFF" ]]; then
  cmake_args+=("-DUSE_SYSTEM_ICU=OFF")
else
  cmake_args+=("-DUSE_SYSTEM_ICU=ON")
fi

if [[ "$(normalize_bool "${TESSERACT_ENABLE_LTO:-}" "ON")" == "OFF" ]]; then
  cmake_args+=("-DENABLE_LTO=OFF")
else
  cmake_args+=("-DENABLE_LTO=ON")
fi

neon_pref=${TESSERACT_ENABLE_NEON:-AUTO}
case "${neon_pref}" in
  AUTO|auto|Auto|"")
    arch=$(uname -m 2>/dev/null || echo unknown)
    if [[ "${arch}" =~ arm64|aarch64|ARM64|ARMv8|ARMV8 ]]; then
      cmake_args+=("-DTESSERACT_NEON=ON")
    elif [[ "${arch}" =~ ^arm ]]; then
      cmake_args+=("-DTESSERACT_NEON=ON")
    fi
    ;;
  1|ON|TRUE|on|true)
    cmake_args+=("-DTESSERACT_NEON=ON")
    ;;
  0|OFF|FALSE|off|false)
    cmake_args+=("-DTESSERACT_NEON=OFF")
    ;;
  *)
    cmake_args+=("-DTESSERACT_NEON=${neon_pref}")
    ;;
esac

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
