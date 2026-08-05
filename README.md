# px4_sitl

Build rules for the XGC2 PX4 v1.14 SITL Debian package on ROS Noetic.

This repository is intentionally small. It does not store PX4 source trees, PX4 binaries, Gazebo plugin binaries, or built `.deb` files. CI clones the configured PX4 tag, builds the SITL runtime and Gazebo Classic plugins in the target Ubuntu/ROS environment, and packages only the runtime artifacts users need.

## Package Model

This branch publishes one user-facing Gazebo Classic Debian package:

```bash
ros-noetic-xgc2-gazebo-sim-px4-1-14
```

The build emits a PX4 SITL runtime package and a Gazebo Classic package. Installing `ros-noetic-xgc2-gazebo-sim-px4-1-14` also installs the matching PX4 runtime dependency and provides these ROS packages under `/opt/ros/noetic`:

```text
px4_sitl_1_14
gazebo_sim_px4_1_14
```

`px4_sitl_1_14` contains PX4 SITL runtime files and helper scripts. `gazebo_sim_px4_1_14` contains the PX4 Gazebo Classic models, worlds, plugin libraries, and combined MAVROS/Gazebo launch file from PX4 v1.14.

The PX4 maintenance line is encoded in the Debian package name. The Debian `Version` tracks the exact PX4 tag plus a packaging revision:

```text
PX4 v1.14.4 -> ros-noetic-xgc2-gazebo-sim-px4-1-14 1.14.4-1
PX4 v1.14.4 packaging fix -> ros-noetic-xgc2-gazebo-sim-px4-1-14 1.14.4-2
```

Other Ubuntu 20.04 compatible PX4 lines can use separate package names such as `ros-noetic-xgc2-gazebo-sim-px4-1-12`. This keeps APT versioning for revisions within the same PX4 line instead of using it to switch major runtime layouts.

## User Installation

Once the self-hosted APT repository is enabled, install the runtime with:

```bash
curl -fsSL https://APT_DOMAIN/xgc2-archive-keyring.gpg | \
  sudo gpg --dearmor -o /usr/share/keyrings/xgc2-archive-keyring.gpg

echo "deb [signed-by=/usr/share/keyrings/xgc2-archive-keyring.gpg arch=amd64] https://APT_DOMAIN focal main" | \
  sudo tee /etc/apt/sources.list.d/xgc2.list

sudo apt update
sudo apt install ros-noetic-xgc2-gazebo-sim-px4-1-14
```

Check available packaging revisions:

```bash
apt-cache madison ros-noetic-xgc2-gazebo-sim-px4-1-14
```

Launch Iris with MAVROS and Gazebo Classic:

```bash
source /opt/ros/noetic/setup.bash
roslaunch gazebo_sim_px4_1_14 iris.launch vehicle:=iris gui:=true
```

Use an external PX4 text parameter file and a tuned SDF from a lightweight
wrapper package:

```bash
source /opt/ros/noetic/setup.bash
roslaunch gazebo_sim_px4_1_14 iris.launch \
  vehicle:=iris \
  px4_sim_model:=gazebo-classic_iris \
  model_name:=fs150_4 \
  ID:=3 \
  work_dir:=$HOME/.xgc2/px4_sitl/fs150_4 \
  param_file:=/path/to/fs150-mav_sys_id4.params \
  sdf:=/path/to/fs150_iris.sdf \
  reset_params:=true
```

The launch file is intended to be reused by lightweight aircraft-specific
wrapper packages. The wrapper can keep tuned assets outside the installed PX4
runtime and pass them through launch arguments:

```text
param_file       PX4 text .params file exported by QGroundControl/PX4 tools.
param_bson       PX4 persistent parameters.bson snapshot.
reset_params     Remove the writable rootfs parameter cache before launch.
sdf              Tuned Gazebo model file.
model_name       Gazebo model instance name.
px4_sim_model    PX4 simulator model name used by the startup scripts.
sys_autostart    Optional PX4 SYS_AUTOSTART override.
startup_script   Runtime-relative or absolute PX4 startup script path.
work_dir         Per-vehicle writable PX4 rootfs directory.
```

## Installed Layout

PX4 SITL runtime:

```text
/opt/ros/noetic/share/px4_sitl_1_14/
├── config/
├── package.xml
└── runtime/
    ├── bin/
    │   ├── px4
    │   ├── px4-alias.sh
    │   └── px4-* -> px4
    ├── etc/
    └── setup.bash
```

Gazebo Classic runtime:

```text
/opt/ros/noetic/share/gazebo_sim_px4_1_14/
├── launch/
├── models/
├── package.xml
└── worlds/

/opt/ros/noetic/lib/gazebo_sim_px4_1_14/
└── lib*.so
```

The launch file uses `/tmp/px4_sitl` as the writable rootfs so generated PX4 files such as `parameters.bson`, `dataman`, and logs do not pollute installed files.

## Local Build

The normal local path builds inside the official ROS Noetic image:

```bash
.xgc2/scripts/build_runtime_deb_in_docker.sh \
  --work-dir /tmp/px4-runtime-work \
  --output-dir debs
```

The script pulls `ros:noetic-ros-base-focal`, clones PX4 v1.14.4, initializes PX4 submodules, installs explicit Gazebo Classic build dependencies, runs PX4's `Tools/setup/ubuntu.sh --no-nuttx` when available, builds `px4_sitl_default` and `sitl_gazebo-classic`, extracts runtime artifacts, runs lightweight runtime checks, builds the Debian package, installs it in the same disposable container, and verifies that both ROS packages are discoverable by `rospack`.

For lower-level debugging, run the stages directly:

```bash
.xgc2/scripts/fetch_px4.sh --work-dir /tmp/px4-runtime-work
.xgc2/scripts/build_px4_runtime.sh --px4-dir /tmp/px4-runtime-work/PX4-Autopilot
.xgc2/scripts/extract_px4_runtime.sh \
  --px4-dir /tmp/px4-runtime-work/PX4-Autopilot \
  --output-dir /tmp/px4-runtime-stage
.xgc2/scripts/extract_gazebo_classic_runtime.sh \
  --px4-dir /tmp/px4-runtime-work/PX4-Autopilot \
  --output-dir /tmp/gazebo-runtime-stage
.xgc2/scripts/check_px4_runtime.sh /tmp/px4-runtime-stage
.xgc2/scripts/build_deb.sh \
  --runtime-dir /tmp/px4-runtime-stage \
  --gazebo-dir /tmp/gazebo-runtime-stage \
  --output-dir debs
```

## Central APT Publication

The `release` workflow builds, installs, checks, and uploads trusted `.deb` and
manifest artifacts. It does not publish directly to the production APT server.
The protected `xgc2-apt-production` environment in `lxk36/xgc2-devops` owns
production publication: its central `release-orchestrator` stages the complete
dependency set and atomically promotes one verified release train.

Do not add APT publishing credentials, SSH deploy keys, private keys, or server
host-key configuration to this product repository or its GitHub Actions
workflows. Product repositories build and attest artifacts only; production
release credentials belong exclusively to the protected central release
environment.

Authoritative release documentation:

- [APT repository and central release-train contract](https://github.com/lxk36/xgc2-devops/blob/master/platforms/apt-repo/README.md#central-release-train-settings)
- [GitHub Actions release orchestrator](https://github.com/lxk36/xgc2-devops/blob/master/.github/workflows/release-orchestrator.yml)

## CI

The `release` GitHub Actions workflow:

1. Reads `manifest/px4_runtime.yaml`.
2. Builds in parallel for `amd64` and `arm64` on native GitHub-hosted runners.
3. Pulls `ros:noetic-ros-base-focal`.
4. Runs the full build inside a disposable Docker container.
5. Clones PX4-Autopilot at the configured tag and initializes all PX4 submodules.
6. Runs PX4's Ubuntu dependency setup when present.
7. Builds `px4_sitl_default` and the Gazebo Classic `sitl_gazebo-classic` target.
8. Extracts PX4 runtime files, Gazebo Classic models, worlds, and plugins.
9. Runs lightweight PX4 runtime and package layout checks.
10. Builds `ros-noetic-xgc2-px4-sitl-1-14` and `ros-noetic-xgc2-gazebo-sim-px4-1-14`.
11. Installs the `.deb` inside the container.
12. Checks `px4_sitl_1_14` and `gazebo_sim_px4_1_14` with `rospack`.
13. Uploads the `.deb` and build manifest as workflow artifacts named by Debian
    architecture.
14. Returns those trusted artifacts to the central release train for staging
    and atomic promotion; this product workflow does not hold production APT
    credentials or publish directly.
