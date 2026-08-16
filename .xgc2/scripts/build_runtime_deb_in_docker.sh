#!/usr/bin/env bash
# shellcheck disable=SC1004 # Inner bash receives and parses these continuations.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=.xgc2/scripts/lib/manifest.sh
source "${SCRIPT_DIR}/lib/manifest.sh"

REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
DOCKER_IMAGE="$(require_manifest_value docker_image)"
WORK_DIR="${PX4_DOCKER_WORK_DIR:-${REPO_ROOT}/.work/docker}"
OUTPUT_DIR="${PX4_DOCKER_OUTPUT_DIR:-${REPO_ROOT}/debs}"
PULL_IMAGE=true
INSTALL_CHECK=true

while [[ $# -gt 0 ]]; do
  case "$1" in
    --image)
      DOCKER_IMAGE="$2"
      shift 2
      ;;
    --work-dir)
      WORK_DIR="$2"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --no-pull)
      PULL_IMAGE=false
      shift
      ;;
    --skip-install-check)
      INSTALL_CHECK=false
      shift
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

APPROVED_DOCKER_IMAGE="$(require_manifest_value docker_image)"
if [[ "${DOCKER_IMAGE}" != "${APPROVED_DOCKER_IMAGE}" ]]; then
  echo "--image must match the approved XGC2 build image: ${APPROVED_DOCKER_IMAGE}" >&2
  exit 1
fi

mkdir -p "${WORK_DIR}" "${OUTPUT_DIR}"

if [[ "${PULL_IMAGE}" == "true" ]]; then
  docker pull "${DOCKER_IMAGE}"
fi

docker run --rm \
  -e XGC2_APT_OVERLAY_URL="${XGC2_APT_OVERLAY_URL:-}" \
  -e DEBIAN_FRONTEND=noninteractive \
  -e INSTALL_CHECK="${INSTALL_CHECK}" \
  -v "${REPO_ROOT}:/workspace/px4_sitl_runtime:ro" \
  -v "${WORK_DIR}:/workspace/work" \
  -v "${OUTPUT_DIR}:/workspace/out" \
  "${DOCKER_IMAGE}" \
  bash -lc '
    set -euo pipefail

    # PX4 build dependencies belong in the approved XGC2 full build image.
    # Fail with the exact missing image inputs instead of mutating the build
    # environment with the PX4 apt/pip bootstrap script.
    required_packages=(
      astyle bc build-essential ccache cmake cppcheck cppzmq-dev file g++ gcc
      gdb genromfs git gz-harmonic gstreamer1.0-libav
      gstreamer1.0-plugins-bad gstreamer1.0-plugins-base
      gstreamer1.0-plugins-good gstreamer1.0-plugins-ugly
      lcov libeigen3-dev libgstreamer-plugins-base1.0-dev
      libimage-exiftool-perl libopencv-dev libssl-dev libxml2-dev
      libxml2-utils make ninja-build pkg-config protobuf-compiler
      python3 python3-dev python3-pip python3-setuptools python3-wheel
      ros-jazzy-ros2pkg rsync shellcheck unzip zip
    )
    missing_packages=()
    for package in "${required_packages[@]}"; do
      if ! dpkg-query -W -f="\${db:Status-Abbrev}" "${package}" 2>/dev/null \
          | grep -q "^ii"; then
        missing_packages+=("${package}")
      fi
    done
    if (( ${#missing_packages[@]} > 0 )); then
      printf "XGC2 build image is missing PX4 package: %s\n" \
        "${missing_packages[@]}" >&2
      exit 1
    fi
    required_python_modules=(
      argcomplete cerberus coverage em future genmsg jinja2 jsonschema
      kconfiglib lxml matplotlib nunavut numpy packaging pandas pkgconfig
      psutil pygments pymavlink pyulog requests serial setuptools six sympy
      toml yaml Crypto
    )
    missing_python_modules=()
    for module in "${required_python_modules[@]}"; do
      if ! python3 -c "import ${module}" >/dev/null 2>&1; then
        missing_python_modules+=("${module}")
      fi
    done
    if (( ${#missing_python_modules[@]} > 0 )); then
      printf "XGC2 build image is missing PX4 Python module: %s\n" \
        "${missing_python_modules[@]}" >&2
      exit 1
    fi

    cd /workspace/px4_sitl_runtime
    PX4_DIR="$(.xgc2/scripts/fetch_px4.sh --work-dir /workspace/work)"

    .xgc2/scripts/build_px4_runtime.sh --px4-dir "${PX4_DIR}"
    .xgc2/scripts/extract_px4_runtime.sh --px4-dir "${PX4_DIR}" --output-dir /workspace/work/runtime-stage
    .xgc2/scripts/extract_gz_sim_runtime.sh --px4-dir "${PX4_DIR}" --output-dir /workspace/work/gz-sim-stage
    .xgc2/scripts/check_px4_runtime.sh /workspace/work/runtime-stage
    .xgc2/scripts/check_gz_sim_runtime.sh /workspace/work/gz-sim-stage
    .xgc2/scripts/build_deb.sh \
      --runtime-dir /workspace/work/runtime-stage \
      --gz-sim-dir /workspace/work/gz-sim-stage \
      --output-dir /workspace/out

    if [[ "${INSTALL_CHECK}" == "true" ]]; then
      apt-get install -y /workspace/out/*.deb
      source .xgc2/scripts/lib/manifest.sh
      INSTALL_PREFIX="$(manifest_value install_prefix)"
      GZ_SIM_RUNTIME_PREFIX="$(manifest_value gazebo_runtime_prefix)"
      RUNTIME_ROS_PACKAGE="$(manifest_value runtime_ros_package)"
      GZ_SIM_ROS_PACKAGE="$(manifest_value gazebo_ros_package)"
      .xgc2/scripts/check_px4_runtime.sh "${INSTALL_PREFIX}"
      .xgc2/scripts/check_gz_sim_runtime.sh "${GZ_SIM_RUNTIME_PREFIX}"
      set +u
      source /opt/ros/jazzy/setup.bash
      set -u
      test "$(ros2 pkg prefix "${RUNTIME_ROS_PACKAGE}")" = "/opt/ros/jazzy"
      test "$(ros2 pkg prefix "${GZ_SIM_ROS_PACKAGE}")" = "/opt/ros/jazzy"
    fi
  '

echo "Debian package output:"
find "${OUTPUT_DIR}" -maxdepth 1 -type f -name "*.deb" -print | sort
