#!/usr/bin/env bash
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

mkdir -p "${WORK_DIR}" "${OUTPUT_DIR}"

if [[ "${PULL_IMAGE}" == "true" ]]; then
  docker pull "${DOCKER_IMAGE}"
fi

docker run --rm \
  -e XGC2_APT_OVERLAY_URL="${XGC2_APT_OVERLAY_URL:-}" \
  -e DEBIAN_FRONTEND=noninteractive \
  -e INSTALL_CHECK="${INSTALL_CHECK}" \
  -v "${REPO_ROOT}:/workspace/px4_sitl:ro" \
  -v "${WORK_DIR}:/workspace/work" \
  -v "${OUTPUT_DIR}:/workspace/out" \
  "${DOCKER_IMAGE}" \
  bash -lc '
    set -euo pipefail

    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y --no-install-recommends \
      bc \
      ca-certificates \
      ccache \
      cmake \
      curl \
      dpkg-dev \
      file \
      g++ \
      gazebo11 \
      gcc \
      genromfs \
      git \
      gnupg \
      libeigen3-dev \
      libgazebo11-dev \
      libopencv-dev \
      libprotobuf-dev \
      libssl-dev \
      libxslt1-dev \
      libxml2-dev \
      libxml2-utils \
      lsb-release \
      make \
      ninja-build \
      protobuf-compiler \
      python3 \
      python3-dev \
      python3-empy \
      python3-jinja2 \
      python3-numpy \
      python3-packaging \
      python3-pip \
      python3-setuptools \
      python3-toml \
      python3-wheel \
      python3-yaml \
      rsync \
      ros-noetic-gazebo-ros \
      ros-noetic-mavlink \
      ros-noetic-mavros \
      ros-noetic-mavros-extras \
      ros-noetic-rospack \
      sudo \
      unzip \
      wget \
      zip

    cd /workspace/px4_sitl
    PX4_DIR="$(.xgc2/scripts/fetch_px4.sh --work-dir /workspace/work)"

    if [[ -x "${PX4_DIR}/Tools/setup/ubuntu.sh" ]]; then
      bash "${PX4_DIR}/Tools/setup/ubuntu.sh" --no-nuttx
    fi

    .xgc2/scripts/build_px4_runtime.sh --px4-dir "${PX4_DIR}"
    .xgc2/scripts/extract_px4_runtime.sh --px4-dir "${PX4_DIR}" --output-dir /workspace/work/runtime-stage
    .xgc2/scripts/extract_gazebo_classic_runtime.sh --px4-dir "${PX4_DIR}" --output-dir /workspace/work/gazebo-stage
    .xgc2/scripts/check_px4_runtime.sh /workspace/work/runtime-stage
    .xgc2/scripts/build_deb.sh \
      --runtime-dir /workspace/work/runtime-stage \
      --gazebo-dir /workspace/work/gazebo-stage \
      --output-dir /workspace/out

    if [[ "${INSTALL_CHECK}" == "true" ]]; then
      apt-get install -y /workspace/out/*.deb
      source .xgc2/scripts/lib/manifest.sh
      INSTALL_PREFIX="$(manifest_value install_prefix)"
      GAZEBO_RUNTIME_PREFIX="$(manifest_value gazebo_runtime_prefix)"
      RUNTIME_ROS_PACKAGE="$(manifest_value runtime_ros_package)"
      GAZEBO_ROS_PACKAGE="$(manifest_value gazebo_ros_package)"
      .xgc2/scripts/check_px4_runtime.sh "${INSTALL_PREFIX}"
      test -f "${GAZEBO_RUNTIME_PREFIX}/models/iris/iris.sdf"
      test -f "${GAZEBO_RUNTIME_PREFIX}/worlds/empty.world"
      set +u
      source /opt/ros/noetic/setup.bash
      set -u
      test "$(rospack find "${RUNTIME_ROS_PACKAGE}")" = "/opt/ros/noetic/share/${RUNTIME_ROS_PACKAGE}"
      test "$(rospack find "${GAZEBO_ROS_PACKAGE}")" = "/opt/ros/noetic/share/${GAZEBO_ROS_PACKAGE}"
      roslaunch --files "${GAZEBO_ROS_PACKAGE}" iris.launch >/tmp/px4-sitl-runtime-launch-files.txt
    fi
  '

echo "Debian package output:"
find "${OUTPUT_DIR}" -maxdepth 1 -type f -name "*.deb" -print | sort
