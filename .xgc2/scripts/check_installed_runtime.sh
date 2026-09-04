#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=.xgc2/scripts/lib/manifest.sh
source "${SCRIPT_DIR}/lib/manifest.sh"

ROS_DISTRO="$(require_manifest_value ros_distro)"
RUNTIME_ROS_PACKAGE="$(require_manifest_value runtime_ros_package)"
GAZEBO_ROS_PACKAGE="$(require_manifest_value gazebo_ros_package)"
INSTALL_PREFIX="$(require_manifest_value install_prefix)"
GAZEBO_RUNTIME_PREFIX="$(require_manifest_value gazebo_runtime_prefix)"
PACKAGE_NAME="$(require_manifest_value package_name)"

if ! dpkg -s "${PACKAGE_NAME}" >/dev/null 2>&1; then
  echo "Debian package is not installed: ${PACKAGE_NAME}" >&2
  exit 1
fi

test -f "/opt/ros/${ROS_DISTRO}/setup.bash"
# shellcheck disable=SC1090
source "/opt/ros/${ROS_DISTRO}/setup.bash"

test "$(rospack find "${RUNTIME_ROS_PACKAGE}")" = "/opt/ros/${ROS_DISTRO}/share/${RUNTIME_ROS_PACKAGE}"
test "$(rospack find "${GAZEBO_ROS_PACKAGE}")" = "/opt/ros/${ROS_DISTRO}/share/${GAZEBO_ROS_PACKAGE}"
grep -Fxq 'udp_offboard_port_local=$((15300+px4_instance))' \
  "/opt/ros/${ROS_DISTRO}/share/${RUNTIME_ROS_PACKAGE}/config/px4-rc.mavlink"
grep -Fxq 'udp_offboard_port_remote=$((15000+px4_instance))' \
  "/opt/ros/${ROS_DISTRO}/share/${RUNTIME_ROS_PACKAGE}/config/px4-rc.mavlink"
if grep -Fq 'udp_offboard_port_remote=14549' \
  "/opt/ros/${ROS_DISTRO}/share/${RUNTIME_ROS_PACKAGE}/config/px4-rc.mavlink"; then
  echo "XGC PX4 MAVLink port script retained the stock shared-port fallback" >&2
  exit 1
fi

"${SCRIPT_DIR}/check_px4_runtime.sh" "${INSTALL_PREFIX}"
test -f "${GAZEBO_RUNTIME_PREFIX}/models/iris/iris.sdf"
test -f "${GAZEBO_RUNTIME_PREFIX}/worlds/empty.world"
roslaunch --files "${GAZEBO_ROS_PACKAGE}" iris.launch >/tmp/xgc2-px4-sitl-launch-files.txt

echo "Installed runtime check passed: ${PACKAGE_NAME}"
