#!/usr/bin/env bash
# Cloud Agent bootstrap for the DevCentr monorepo.
#
# Installs everything needed to build and run the D desktop app (under app/)
# and to build the Antora docs (under docs/). Written to be idempotent so it
# can safely run against a cached or partially prepared environment.
set -euo pipefail

LDC_VERSION="ldc-1.42.0"
DLANG_DIR="${HOME}/dlang"
LDC_BIN="${DLANG_DIR}/${LDC_VERSION}/bin"

echo "==> Installing system libraries (build tools + dlangui runtime deps)"
# dlangui renders through OpenGL/SDL2 and loads fonts via FreeType, so the app
# needs the OpenGL, SDL2, FreeType, and X11 development libraries to build/run.
sudo apt-get update -qq
sudo apt-get install -y --no-install-recommends \
  ca-certificates curl xz-utils git build-essential pkg-config \
  libgl1-mesa-dev libglu1-mesa-dev libsdl2-dev libfreetype6-dev \
  libx11-dev libxext-dev libxcursor-dev libxinerama-dev libxi-dev \
  libxrandr-dev libxss-dev libdbus-1-dev \
  fonts-dejavu-core fonts-liberation

echo "==> Installing D toolchain (${LDC_VERSION}) + dub"
# Matches CI's ldc-latest line (release.yml). LDC ships dub, so no separate dub.
if [ ! -x "${LDC_BIN}/ldc2" ]; then
  curl -fsSL https://dlang.org/install.sh -o /tmp/install-d.sh
  bash /tmp/install-d.sh "${LDC_VERSION}"
fi
# Put ldc2/ldmd2/dub on the default PATH so no `source activate` is needed.
# LDC resolves its ldc2.conf via the binary's real path, so symlinks are safe.
for tool in ldc2 ldmd2 dub; do
  sudo ln -sf "${LDC_BIN}/${tool}" "/usr/local/bin/${tool}"
done

echo "==> Installing Node dependencies (docs + app catalog)"
corepack enable >/dev/null 2>&1 || true
pnpm install --frozen-lockfile
(cd app && pnpm install --frozen-lockfile)

echo "==> Building the DevCentr app (verifies the toolchain end-to-end)"
(cd app && dub build --build=debug)

echo "==> Setup complete: 'cd app && dub build' to build, run ./app/DevCentr under a display."
