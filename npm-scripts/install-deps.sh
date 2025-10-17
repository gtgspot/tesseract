#!/usr/bin/env bash
set -euo pipefail

if ! command -v apt-get >/dev/null 2>&1; then
  echo "apt-get not available, skipping system dependency installation" >&2
  exit 0
fi

export DEBIAN_FRONTEND=${DEBIAN_FRONTEND:-noninteractive}

packages=(
  apt-utils
  libleptonica-dev
  libfmt-dev
  libarchive-dev
  libomp-dev
  libcairo2-dev
  libpango1.0-dev
  libfontconfig1-dev
  libfreetype6-dev
  libicu-dev
  pkg-config
)

missing_packages=()
for pkg in "${packages[@]}"; do
  if ! dpkg -s "$pkg" >/dev/null 2>&1; then
    missing_packages+=("$pkg")
  fi
done

apt_updated=false

if ((${#missing_packages[@]})); then
  apt-get update
  apt_updated=true
  apt-get install -y --no-install-recommends "${missing_packages[@]}"
else
  echo "Required APT packages already installed" >&2
fi

# libfmt8 is required on older Debian/Ubuntu derivatives. Install it when the
# archive provides the package, otherwise rely on the version bundled with
# libfmt-dev (which may provide libfmt9 or newer).
if ! dpkg -s libfmt8 >/dev/null 2>&1; then
  if ! $apt_updated; then
    apt-get update
    apt_updated=true
  fi
  if apt-cache show libfmt8 >/dev/null 2>&1; then
    apt-get install -y --no-install-recommends libfmt8
  else
    echo "libfmt8 package not available in current apt sources; relying on libfmt-dev" >&2
  fi
fi
