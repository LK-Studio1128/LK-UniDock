#!/usr/bin/env bash
# build_mac.sh — Build Uni-Dock on macOS (CPU-only)
#
# IMPORTANT: Apple Silicon (M1/M2/M3/M4) does NOT support NVIDIA CUDA.
#   This script always builds the CPU-only version.
#   Intel Macs with old NVIDIA GPUs (pre-2014) are also not supported
#   because NVIDIA dropped macOS CUDA support after macOS 10.14.
#
# Prerequisites:
#   Xcode Command Line Tools:  xcode-select --install
#   Homebrew:  https://brew.sh
#   CMake:     brew install cmake
#   Boost:     brew install boost
#   OpenMP:    brew install libomp        (required — Apple Clang lacks built-in OpenMP)
#
# Usage:
#   bash build_mac.sh               # build with system Boost
#   bash build_mac.sh --fetch-boost  # auto-download Boost via CMake FetchContent
#   bash build_mac.sh --clean        # clean build (delete build dir first)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/unidock/build"
SOURCE_DIR="${SCRIPT_DIR}/unidock"
DIST_DIR="${SCRIPT_DIR}/dist"

FETCH_BOOST=OFF
PORTABLE=ON
CLEAN=OFF
for arg in "$@"; do
  case $arg in
    --fetch-boost) FETCH_BOOST=ON ;;
    --no-portable) PORTABLE=OFF ;;
    --clean)       CLEAN=ON ;;
  esac
done

ARCH="$(uname -m)"

echo "=== Uni-Dock macOS Build (CPU-only) ==="
echo "  Source     : ${SOURCE_DIR}"
echo "  Build      : ${BUILD_DIR}"
echo "  Arch       : ${ARCH}"
echo "  Fetch Boost: ${FETCH_BOOST}"
echo "  Portable   : ${PORTABLE}  (static Boost+OpenMP)"
echo ""

# ── Force system Apple Clang (avoid conda/mamba compiler that injects rpath) ──
export CC=/usr/bin/cc
export CXX=/usr/bin/c++

# ── Isolate from conda: unset env vars that inject conda paths into compiler/linker ──
unset CFLAGS CXXFLAGS LDFLAGS CPPFLAGS
unset CMAKE_PREFIX_PATH CMAKE_ARGS
unset CONDA_BUILD_SYSROOT
echo "  CC  : ${CC}"
echo "  CXX : ${CXX}"
if [[ -n "${CONDA_PREFIX:-}" ]]; then
  echo "  NOTE: conda is active (CONDA_PREFIX=${CONDA_PREFIX})."
  echo "        CFLAGS/CXXFLAGS/LDFLAGS have been unset to prevent conda libomp/libc++ contamination."
fi
echo ""

# Check for required dependencies
if ! command -v cmake &>/dev/null; then
  echo "ERROR: cmake not found. Install via: brew install cmake"; exit 1
fi
if ! brew list libomp &>/dev/null 2>&1; then
  echo "WARNING: Homebrew libomp not found."
  echo "  Multi-threaded docking will be disabled."
  echo "  Install with: brew install libomp"
fi

if [[ "${CLEAN}" == "ON" && -d "${BUILD_DIR}" ]]; then
  echo "Cleaning build dir..."
  rm -rf "${BUILD_DIR}"
fi

mkdir -p "${BUILD_DIR}" "${DIST_DIR}"

cmake -S "${SOURCE_DIR}" -B "${BUILD_DIR}" \
  -DCMAKE_C_COMPILER="${CC}" \
  -DCMAKE_CXX_COMPILER="${CXX}" \
  -DCMAKE_BUILD_TYPE=Release \
  -DFORCE_CPU_ONLY=ON \
  -DFETCH_BOOST="${FETCH_BOOST}" \
  -DBUILD_PORTABLE="${PORTABLE}"

cmake --build "${BUILD_DIR}" -j"$(sysctl -n hw.logicalcpu)"

# ── Copy + rename to match LKDock ENGINE_FILE_CANDIDATES ──
BIN_SRC="${BUILD_DIR}/unidock"
BIN_DST="${DIST_DIR}/Uni-Dock"
if [[ -f "${BIN_SRC}" ]]; then
  cp "${BIN_SRC}" "${BIN_DST}"
  chmod +x "${BIN_DST}"
fi

echo ""
echo "=== Build complete (CPU-only, ${ARCH}) ==="
echo "Binary : ${BIN_DST}"

# ── Verify portability ──
if command -v otool &>/dev/null && [[ -f "${BIN_DST}" ]]; then
  echo "Dynamic dependencies:"
  otool -L "${BIN_DST}" | tail -n +2
  NEEDS_BUNDLE=0
  if otool -L "${BIN_DST}" | grep -q '@rpath/libomp'; then
    echo "WARNING: Binary dynamically links libomp via @rpath."
    NEEDS_BUNDLE=1
  fi
  if otool -L "${BIN_DST}" | grep -q '@rpath/libc++'; then
    echo "WARNING: Binary dynamically links libc++ via @rpath (conda contamination)."
    NEEDS_BUNDLE=1
  fi
  if [[ ${NEEDS_BUNDLE} -eq 0 ]]; then
    echo "OK: Fully portable — only depends on macOS system libraries."
  else
    echo ""
    echo "FIX: Re-run with conda deactivated:  conda deactivate && bash build_mac.sh --clean"
    echo "  Or the script should have already unset CFLAGS/LDFLAGS above."
  fi
fi
echo ""
echo "NOTE: This binary runs on CPU only. For GPU acceleration use Linux + NVIDIA GPU."
