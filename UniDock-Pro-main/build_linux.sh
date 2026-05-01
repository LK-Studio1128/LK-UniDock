#!/usr/bin/env bash
# build_linux.sh — Build UniDock-Pro on Linux
# Prerequisites:
#   NVIDIA GPU + CUDA Toolkit >= 11.8
#   CMake >= 3.16,  GCC compatible with NVCC
#   Boost >= 1.72  OR use -DFETCH_BOOST=ON
#   OpenMP (included with GCC)
#
# Usage:
#   bash build_linux.sh                 # build both GPU and CPU variants
#   bash build_linux.sh --cpu-only      # build CPU variant only
#   bash build_linux.sh --gpu-only      # build GPU variant only
#   bash build_linux.sh --fetch-boost   # auto-download Boost

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST_DIR="${SCRIPT_DIR}/dist"

FETCH_BOOST=OFF
PORTABLE=ON
BUILD_CPU=ON
BUILD_GPU=ON
for arg in "$@"; do
  case $arg in
    --cpu|--cpu-only) BUILD_GPU=OFF ;;
    --gpu-only)    BUILD_CPU=OFF ;;
    --fetch-boost) FETCH_BOOST=ON ;;
    --no-portable) PORTABLE=OFF ;;
  esac
done

if [[ "${BUILD_CPU}" == "OFF" && "${BUILD_GPU}" == "OFF" ]]; then
  echo "ERROR: both CPU and GPU builds are disabled."
  exit 1
fi

if command -v nproc >/dev/null 2>&1; then
  BUILD_JOBS="$(nproc)"
else
  BUILD_JOBS="$(getconf _NPROCESSORS_ONLN)"
fi

ARCH="$(uname -m)"

echo "=== UniDock-Pro Linux Build ==="
echo "  Source   : ${SCRIPT_DIR}"
echo "  Portable : ${PORTABLE}  (static Boost/libstdc++)"
echo "  Build CPU: ${BUILD_CPU}"
echo "  Build GPU: ${BUILD_GPU}"
echo ""

# ── Isolate from conda (if active) ──
unset CFLAGS CXXFLAGS LDFLAGS CPPFLAGS
unset CMAKE_PREFIX_PATH CMAKE_ARGS
if [[ -n "${CONDA_PREFIX:-}" ]]; then
  echo "  NOTE: conda env vars (CFLAGS/LDFLAGS) cleared to avoid contamination."
  echo ""
fi

CMAKE_EXTRA_ARGS=()
if [[ "${PORTABLE}" == "ON" ]]; then
  CMAKE_EXTRA_ARGS+=("-DCMAKE_BUILD_RPATH=\$ORIGIN/.libs")
  CMAKE_EXTRA_ARGS+=("-DCMAKE_INSTALL_RPATH=\$ORIGIN/.libs")
fi

mkdir -p "${DIST_DIR}"

print_summary_list() {
  local title="$1"
  shift
  echo "  ${title}"
  if [[ "$#" -eq 0 ]]; then
    echo "    (none)"
  else
    printf '%s\n' "$@" | awk 'NF && !seen[$0]++ {print "    " $0}'
  fi
}

bundle_runtime() {
  local bin_path="$1"
  local bundle_lib_dir="$2"
  local dep_line dep_path dep_name dep_key
  local -a bundled_libs=()
  local -a system_libs=()
  local -a unresolved_libs=()
  [[ "${PORTABLE}" == "ON" ]] || return 0
  [[ -f "${bin_path}" ]] || return 0
  mkdir -p "${bundle_lib_dir}"
  if ! command -v ldd >/dev/null 2>&1; then
    echo "  WARNING: ldd not found; skipping runtime dependency scan."
    return 0
  fi
  while IFS= read -r dep_line; do
    dep_name="$(printf '%s\n' "${dep_line}" | awk '{print $1}')"
    [[ -n "${dep_name}" ]] || continue
    dep_key="${dep_name}"
    if [[ "${dep_key}" == /* ]]; then
      dep_key="$(basename "${dep_key}")"
    fi
    if [[ "${dep_line}" == *"=> not found"* ]]; then
      unresolved_libs+=("${dep_key}")
      continue
    fi
    dep_path="$(printf '%s\n' "${dep_line}" | awk '/=>/ && $3 ~ /^\// {print $3}')"
    if [[ -z "${dep_path}" ]]; then
      dep_path="$(printf '%s\n' "${dep_line}" | awk '$1 ~ /^\// {print $1}')"
    fi
    case "${dep_key}" in
      libc.so.*|libm.so.*|libpthread.so.*|librt.so.*|libdl.so.*|libutil.so.*|libresolv.so.*|libnsl.so.*|ld-linux*.so*|ld-musl-*.so*|linux-vdso.so*|libcuda.so*|libnvidia-*.so*|libnv*.so*|libGLX_nvidia.so*|libEGL_nvidia.so*|libOpenCL.so*|libGLdispatch.so*)
        system_libs+=("${dep_key}")
        continue
        ;;
    esac
    [[ -n "${dep_path}" ]] || continue
    dep_name="$(basename "${dep_path}")"
    cp -Lf "${dep_path}" "${bundle_lib_dir}/${dep_name}"
    bundled_libs+=("${dep_key}")
  done < <(ldd "${bin_path}" || true)
  echo "  Dependencies:"
  ldd "${bin_path}" || true
  print_summary_list "Bundled libraries:" "${bundled_libs[@]}"
  print_summary_list "System-provided libraries:" "${system_libs[@]}"
  print_summary_list "Unresolved libraries:" "${unresolved_libs[@]}"
  if ldd "${bin_path}" 2>/dev/null | grep -Eq 'libc\.so\.6|ld-linux'; then
    echo "  NOTE: glibc remains system-provided; build on an older Linux distro for widest portability."
  fi
  if ldd "${bin_path}" 2>/dev/null | grep -Eq 'libcuda\.so|libnvidia'; then
    echo "  NOTE: NVIDIA driver libraries are not bundled; GPU builds still require a compatible target driver."
  fi
}

build_variant() {
  local variant="$1"
  local cpu_only="$2"
  local require_cuda="$3"
  local build_dir="$4"
  local output_name="$5"
  local bundle_dir="${DIST_DIR}/${output_name}.bundle"
  local bin_path="${bundle_dir}/${output_name}"

  echo "--- Building ${variant} variant ---"
  cmake -S "${SCRIPT_DIR}" -B "${build_dir}" -G "Unix Makefiles" \
    -DCMAKE_BUILD_TYPE=Release \
    -DFORCE_CPU_ONLY="${cpu_only}" \
    -DREQUIRE_CUDA="${require_cuda}" \
    -DFETCH_BOOST="${FETCH_BOOST}" \
    -DBUILD_PORTABLE="${PORTABLE}" \
    "${CMAKE_EXTRA_ARGS[@]}"

  cmake --build "${build_dir}" -j"${BUILD_JOBS}"

  rm -rf "${bundle_dir}"
  mkdir -p "${bundle_dir}"
  cp "${build_dir}/udp" "${bin_path}"
  chmod +x "${bin_path}"
  echo "  Output: ${bin_path}"
  bundle_runtime "${bin_path}" "${bundle_dir}/.libs"
}

if [[ "${BUILD_CPU}" == "ON" ]]; then
  build_variant "CPU" ON OFF "${SCRIPT_DIR}/build_cpu" "UniDock-Pro"
fi

if [[ "${BUILD_GPU}" == "ON" ]]; then
  build_variant "GPU" OFF ON "${SCRIPT_DIR}/build_gpu" "UniDock-Pro-GPU"
fi

echo ""
echo "=== Build complete ==="
echo "Dist dir: ${DIST_DIR}"
