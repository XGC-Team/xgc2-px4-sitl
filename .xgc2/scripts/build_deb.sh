#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=.xgc2/scripts/lib/manifest.sh
source "${SCRIPT_DIR}/lib/manifest.sh"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

RUNTIME_DIR="${RUNTIME_DIR:-}"
GAZEBO_DIR="${GAZEBO_DIR:-}"
OUTPUT_DIR="${OUTPUT_DIR:-${PWD}/debs}"
product_version() {
  awk -F': *' '/^version:[[:space:]]*/ {print $2; exit}' "${REPO_ROOT}/.xgc2/product.yml"
}

PACKAGE_VERSION="${PACKAGE_VERSION:-$(product_version)}"
if [[ -z "${PACKAGE_VERSION}" ]]; then
  echo "package version is missing; set PACKAGE_VERSION or .xgc2/product.yml version" >&2
  exit 1
fi
UPSTREAM_VERSION="${PACKAGE_VERSION%%-*}"
ROS_DISTRO="$(require_manifest_value ros_distro)"
RUNTIME_ROS_PACKAGE="$(require_manifest_value runtime_ros_package)"
GAZEBO_ROS_PACKAGE="$(require_manifest_value gazebo_ros_package)"
INSTALL_PREFIX="$(require_manifest_value install_prefix)"
GAZEBO_RUNTIME_PREFIX="$(require_manifest_value gazebo_runtime_prefix)"
GAZEBO_PLUGIN_PREFIX="$(require_manifest_value gazebo_plugin_prefix)"
PX4_TAG="$(require_manifest_value px4_tag)"
PX4_LINE="${PX4_TAG#v}"
PX4_LINE="${PX4_LINE%.*}"
ARCHITECTURE="${ARCHITECTURE:-$(dpkg --print-architecture)}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --runtime-dir)
      RUNTIME_DIR="$2"
      shift 2
      ;;
    --gazebo-dir)
      GAZEBO_DIR="$2"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --architecture)
      ARCHITECTURE="$2"
      shift 2
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "${RUNTIME_DIR}" || ! -d "${RUNTIME_DIR}" ]]; then
  echo "--runtime-dir is required and must point to extracted PX4 runtime files" >&2
  exit 1
fi
if [[ -z "${GAZEBO_DIR}" || ! -d "${GAZEBO_DIR}" ]]; then
  echo "--gazebo-dir is required and must point to extracted PX4 Gazebo Classic files" >&2
  exit 1
fi

test -x "${RUNTIME_DIR}/bin/px4"
test -f "${RUNTIME_DIR}/bin/px4-alias.sh"
test -d "${RUNTIME_DIR}/etc"
test -d "${GAZEBO_DIR}/lib"
test -d "${GAZEBO_DIR}/models"
test -d "${GAZEBO_DIR}/worlds"
test -f "${GAZEBO_DIR}/models/iris/iris.sdf"
test -f "${GAZEBO_DIR}/worlds/empty.world"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT

ROS_PREFIX="/opt/ros/${ROS_DISTRO}"
RUNTIME_DEB_PACKAGE="ros-${ROS_DISTRO}-xgc2-px4-sitl-${PX4_LINE//./-}"
GAZEBO_DEB_PACKAGE="ros-${ROS_DISTRO}-xgc2-gazebo-sim-px4-${PX4_LINE//./-}"

build_deb() {
  local pkg_root="$1"
  local package_name="$2"
  local architecture="$3"
  mkdir -p "${OUTPUT_DIR}"
  local deb_path="${OUTPUT_DIR}/${package_name}_${PACKAGE_VERSION}_${architecture}.deb"
  dpkg-deb --root-owner-group --build "${pkg_root}" "${deb_path}" >&2
  echo "${deb_path}"
}

write_control() {
  local pkg_root="$1"
  local package_name="$2"
  local architecture="$3"
  local depends="$4"
  local description="$5"
  local details="$6"
  local installed_size
  installed_size="$(du -ks "${pkg_root}" | awk '{print $1}')"
  cat > "${pkg_root}/DEBIAN/control" <<CONTROL
Package: ${package_name}
Version: ${PACKAGE_VERSION}
Section: misc
Priority: optional
Architecture: ${architecture}
Installed-Size: ${installed_size}
Maintainer: XGC2 <xgc2@example.com>
Depends: ${depends}
Description: ${description}
 ${details}
CONTROL
}

remove_packaged_path() {
  local pkg_root="$1"
  local absolute_path="$2"
  if [[ "${absolute_path}" != /* ]]; then
    echo "package cleanup path must be absolute: ${absolute_path}" >&2
    exit 1
  fi
  rm -rf "${pkg_root}${absolute_path}"
}

package_payload_files() {
  local pkg_root="$1"
  find "${pkg_root}" -mindepth 1 \( -type f -o -type l \) ! -path "${pkg_root}/DEBIAN/*" -printf '/%P\n' | sort
}

assert_no_overlapping_payloads() {
  local left_name="$1"
  local left_root="$2"
  local right_name="$3"
  local right_root="$4"
  local left_list
  local right_list
  local overlap
  left_list="$(mktemp)"
  right_list="$(mktemp)"
  package_payload_files "${left_root}" > "${left_list}"
  package_payload_files "${right_root}" > "${right_list}"
  overlap="$(comm -12 "${left_list}" "${right_list}" || true)"
  rm -f "${left_list}" "${right_list}"
  if [[ -n "${overlap}" ]]; then
    echo "package payload overlap between ${left_name} and ${right_name}:" >&2
    printf '%s\n' "${overlap}" >&2
    exit 1
  fi
}

runtime_root="${WORK_DIR}/${RUNTIME_DEB_PACKAGE}_${PACKAGE_VERSION}_${ARCHITECTURE}"
runtime_share="${runtime_root}${ROS_PREFIX}/share/${RUNTIME_ROS_PACKAGE}"
runtime_lib="${runtime_root}${ROS_PREFIX}/lib/${RUNTIME_ROS_PACKAGE}"
mkdir -p "${runtime_root}/DEBIAN" "${runtime_share}/runtime" "${runtime_share}/config" "${runtime_lib}"
cp -a "${RUNTIME_DIR}/." "${runtime_root}${INSTALL_PREFIX}/"
remove_packaged_path "${runtime_root}" "${GAZEBO_RUNTIME_PREFIX}"
remove_packaged_path "${runtime_root}" "${GAZEBO_PLUGIN_PREFIX}"
install -m 0755 "${REPO_ROOT}/scripts/run_px4_sitl.sh" "${runtime_lib}/run_px4_sitl.sh"
install -m 0755 "${REPO_ROOT}/scripts/setup_runtime_env.sh" "${runtime_lib}/setup_runtime_env.sh"
install -m 0644 "${REPO_ROOT}/config/runtime.env" "${runtime_share}/config/runtime.env"
install -m 0644 "${REPO_ROOT}/config/px4-rc.mavlink" "${runtime_share}/config/px4-rc.mavlink"

cat > "${runtime_share}/package.xml" <<EOF_XML
<?xml version="1.0"?>
<package format="2">
  <name>${RUNTIME_ROS_PACKAGE}</name>
  <version>${UPSTREAM_VERSION}</version>
  <description>PX4 v${PX4_LINE} SITL runtime wrapper for ROS Noetic.</description>
  <maintainer email="xgc2@example.com">XGC2</maintainer>
  <license>BSD-3-Clause</license>
  <exec_depend>bash</exec_depend>
</package>
EOF_XML

cat > "${runtime_root}${INSTALL_PREFIX}/setup.bash" <<EOF_SETUP
#!/usr/bin/env bash
export PX4_SITL_RUNTIME_ROOT="${INSTALL_PREFIX}"
export PATH="\${PX4_SITL_RUNTIME_ROOT}/bin:\${PATH}"
EOF_SETUP
chmod 0755 "${runtime_root}${INSTALL_PREFIX}/setup.bash"

write_control \
  "${runtime_root}" \
  "${RUNTIME_DEB_PACKAGE}" \
  "${ARCHITECTURE}" \
  "libc6, libstdc++6, libgcc-s1 | libgcc1" \
  "PX4 v${PX4_LINE} SITL runtime wrapper for ROS Noetic" \
  "Installs the ${RUNTIME_ROS_PACKAGE} ROS package extracted from PX4-Autopilot ${PX4_TAG}."

gazebo_root="${WORK_DIR}/${GAZEBO_DEB_PACKAGE}_${PACKAGE_VERSION}_${ARCHITECTURE}"
gazebo_share="${gazebo_root}${ROS_PREFIX}/share/${GAZEBO_ROS_PACKAGE}"
gazebo_lib="${gazebo_root}${ROS_PREFIX}/lib/${GAZEBO_ROS_PACKAGE}"
mkdir -p "${gazebo_root}/DEBIAN" "${gazebo_share}/launch" "${gazebo_lib}"
cp -a "${GAZEBO_DIR}/models" "${gazebo_share}/models"
cp -a "${GAZEBO_DIR}/worlds" "${gazebo_share}/worlds"
find "${GAZEBO_DIR}/lib" -maxdepth 1 -type f -name '*.so' -exec cp -a {} "${gazebo_lib}/" \;
install -m 0644 "${REPO_ROOT}/launch/iris.launch" "${gazebo_share}/launch/iris.launch"
install -m 0755 "${REPO_ROOT}/scripts/spawn_sdf_model.py" "${gazebo_lib}/spawn_sdf_model.py"

cat > "${gazebo_share}/package.xml" <<EOF_XML
<?xml version="1.0"?>
<package format="2">
  <name>${GAZEBO_ROS_PACKAGE}</name>
  <version>${UPSTREAM_VERSION}</version>
  <description>PX4 v${PX4_LINE} Gazebo Classic models, worlds, and plugins for ROS Noetic.</description>
  <maintainer email="xgc2@example.com">XGC2</maintainer>
  <license>BSD</license>
  <exec_depend>${RUNTIME_ROS_PACKAGE}</exec_depend>
  <exec_depend>gazebo_msgs</exec_depend>
  <exec_depend>gazebo_ros</exec_depend>
  <exec_depend>geometry_msgs</exec_depend>
  <exec_depend>mavlink</exec_depend>
  <exec_depend>mavros</exec_depend>
  <exec_depend>mavros_msgs</exec_depend>
  <exec_depend>python3</exec_depend>
  <exec_depend>rospy</exec_depend>
  <exec_depend>roscpp</exec_depend>
  <exec_depend>sensor_msgs</exec_depend>
  <exec_depend>std_msgs</exec_depend>
  <export>
    <gazebo_ros plugin_path="${GAZEBO_PLUGIN_PREFIX}" gazebo_media_path="\${prefix}" gazebo_model_path="\${prefix}/models"/>
  </export>
</package>
EOF_XML

write_control \
  "${gazebo_root}" \
  "${GAZEBO_DEB_PACKAGE}" \
  "${ARCHITECTURE}" \
  "${RUNTIME_DEB_PACKAGE} (= ${PACKAGE_VERSION}), gazebo11, gstreamer1.0-plugins-bad, gstreamer1.0-plugins-good, gstreamer1.0-plugins-ugly, python3, ros-noetic-gazebo-msgs, ros-noetic-gazebo-ros, ros-noetic-geometry-msgs, ros-noetic-mavlink, ros-noetic-mavros, ros-noetic-mavros-msgs, ros-noetic-rospy, ros-noetic-roscpp, ros-noetic-sensor-msgs, ros-noetic-std-msgs" \
  "PX4 v${PX4_LINE} Gazebo Classic backend for ROS Noetic" \
  "Installs PX4 Gazebo Classic models, worlds, plugins, and launch entrypoints for PX4-Autopilot ${PX4_TAG}."

assert_no_overlapping_payloads "${RUNTIME_DEB_PACKAGE}" "${runtime_root}" "${GAZEBO_DEB_PACKAGE}" "${gazebo_root}"

build_deb "${gazebo_root}" "${GAZEBO_DEB_PACKAGE}" "${ARCHITECTURE}"
build_deb "${runtime_root}" "${RUNTIME_DEB_PACKAGE}" "${ARCHITECTURE}"
