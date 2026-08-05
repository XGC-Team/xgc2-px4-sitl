# XGC2 PX4 SITL Runtime Packages

This repository builds installable Debian packages for selected PX4 SITL
runtime lines. It is intentionally small: it does not store PX4 source trees,
PX4 binaries, Gazebo binaries, or generated `.deb` artifacts. GitHub Actions
clones the configured PX4 tag, builds in the target ROS/Ubuntu environment,
extracts only the runtime files, packages them as `.deb`, and uploads them as
trusted artifacts for the central XGC2 release train.

## Branches And Packages

Each active branch maps to one PX4/ROS/Ubuntu runtime line:

| Branch | PX4 tag | ROS | Ubuntu APT distribution | Gazebo stack | Debian package |
| --- | --- | --- | --- | --- | --- |
| `v1.12-noetic` | `v1.12.3` | ROS Noetic | `focal` | Gazebo Classic | `ros-noetic-xgc2-gazebo-sim-px4-1-12` |
| `v1.14-noetic` | `v1.14.4` | ROS Noetic | `focal` | Gazebo Classic | `ros-noetic-xgc2-gazebo-sim-px4-1-14` |
| `v1.16-jazzy` | `v1.16.2` | ROS 2 Jazzy | `noble` | Gazebo Sim Harmonic | `ros-jazzy-xgc2-gz-harmonic-px4-1-16` |

The package name encodes the PX4 maintenance line. Debian package versions track
the PX4 tag plus a packaging revision, for example `1.12.3-1` then `1.12.3-2`.

## What Gets Installed

`v1.12-noetic` installs:

```text
px4_sitl_1_12
gazebo_sim_px4_1_12
```

`v1.14-noetic` installs:

```text
px4_sitl_1_14
gazebo_sim_px4_1_14
```

`v1.16-jazzy` installs:

```text
px4_sitl_1_16
px4_gz_sim_1_16
```

The PX4 SITL runtime packages contain only PX4 executable files and helper
scripts. The Gazebo packages contain models, worlds, and plugin assets. The
Gazebo packages depend on the matching PX4 SITL runtime package, so installing
the Gazebo package is the normal complete simulator install.

## CI Build

The centrally dispatched `release` workflow prepares one runtime line at a
time. For each branch it:

1. Reads `manifest/px4_runtime.yaml`.
2. Builds on native `amd64` and `arm64` GitHub-hosted runners.
3. Pulls the branch-specific ROS Docker image.
4. Clones PX4-Autopilot at the configured tag.
5. Initializes PX4 submodules.
6. Installs build dependencies inside a disposable container.
7. Builds the PX4 SITL target and matching Gazebo runtime.
8. Extracts runtime files into package staging directories.
9. Builds the Debian package.
10. Installs the package inside the build container.
11. Verifies package discovery with `rospack` or `ros2 pkg prefix`.
12. Uploads the `.deb` files and build manifests as GitHub Actions artifacts.
13. Returns those trusted artifacts to the central release train for staging
    and atomic promotion.

This product workflow never publishes directly to the production APT server.

## Central APT Publication

Production publication is owned by the protected `xgc2-apt-production`
environment in `lxk36/xgc2-devops`. The central `release-orchestrator` consumes
this repository's trusted build artifacts, stages the complete dependency set,
and promotes one verified release train atomically.

Do not add APT publishing credentials, SSH deploy keys, private keys, or server
host-key configuration to this product repository or its GitHub Actions
workflows. Product repositories build and attest artifacts only; production
release credentials belong exclusively to the protected central release
environment.

Authoritative release documentation:

- [APT repository and central release-train contract](https://github.com/lxk36/xgc2-devops/blob/master/platforms/apt-repo/README.md#central-release-train-settings)
- [GitHub Actions release orchestrator](https://github.com/lxk36/xgc2-devops/blob/master/.github/workflows/release-orchestrator.yml)

## Install From Your APT Repository

After the central release train publishes successfully, clients install through
the public HTTPS APT endpoint. Replace `APT_BASE_URL` with the deployment's
repository base URL.

Install the repository signing key:

```bash
APT_BASE_URL=https://apt.example.com

curl -fsSL "$APT_BASE_URL/xgc2-archive-keyring.gpg" | \
  sudo gpg --dearmor -o /usr/share/keyrings/xgc2-archive-keyring.gpg
```

For ROS Noetic / Ubuntu 20.04 `focal`:

```bash
APT_BASE_URL=https://apt.example.com

echo "deb [signed-by=/usr/share/keyrings/xgc2-archive-keyring.gpg arch=amd64] $APT_BASE_URL focal main" | \
  sudo tee /etc/apt/sources.list.d/xgc2-px4-sitl.list

sudo apt update
sudo apt install ros-noetic-xgc2-gazebo-sim-px4-1-12
sudo apt install ros-noetic-xgc2-gazebo-sim-px4-1-14
```

For ROS 2 Jazzy / Ubuntu 24.04 `noble`:

```bash
APT_BASE_URL=https://apt.example.com

echo "deb [signed-by=/usr/share/keyrings/xgc2-archive-keyring.gpg arch=amd64] $APT_BASE_URL noble main" | \
  sudo tee /etc/apt/sources.list.d/xgc2-px4-sitl.list

sudo apt update
sudo apt install ros-jazzy-xgc2-gz-harmonic-px4-1-16
```

Check available package versions:

```bash
apt-cache madison ros-noetic-xgc2-gazebo-sim-px4-1-12
apt-cache madison ros-noetic-xgc2-gazebo-sim-px4-1-14
apt-cache madison ros-jazzy-xgc2-gz-harmonic-px4-1-16
```

## Launch Examples

PX4 v1.12 / ROS Noetic:

```bash
source /opt/ros/noetic/setup.bash
roslaunch gazebo_sim_px4_1_12 iris.launch vehicle:=iris gui:=true
```

Use an external PX4 text parameter file and a tuned SDF from a lightweight
wrapper package:

```bash
source /opt/ros/noetic/setup.bash
roslaunch gazebo_sim_px4_1_12 iris.launch \
  vehicle:=iris \
  px4_sim_model:=iris \
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

To attach a vehicle to an already-running Gazebo Classic server, pass
`start_gazebo:=false`. In that mode the launch still starts PX4, spawns the SDF
through the existing `/gazebo/spawn_sdf_model` service, and starts MAVROS, but
it never includes `gazebo_ros/empty_world.launch`. Set `ROS_MASTER_URI` and
`GAZEBO_MASTER_URI` in the `roslaunch` process environment before invocation.
For multiple attached vehicles, give each one a distinct `ID`, `model_name`,
`work_dir`, SITL/Gazebo MAVLink port set, MAVROS local/remote port pair, and
`sitl_node_name`. `mav_system_id` controls the PX4 `MAV_SYS_ID` independently
from the process instance while `mavros_tgt_system` controls the MAVROS target.

PX4 v1.14 / ROS Noetic:

```bash
source /opt/ros/noetic/setup.bash
roslaunch gazebo_sim_px4_1_14 iris.launch vehicle:=iris gui:=true
```

PX4 v1.16 / ROS 2 Jazzy:

```bash
source /opt/ros/jazzy/setup.bash
ros2 pkg prefix px4_sitl_1_16
ros2 pkg prefix px4_gz_sim_1_16
```

Run the packaged Gazebo Sim helper:

```bash
ros2 run px4_gz_sim_1_16 simulation-gazebo --world default
```

## Local Build

Build the current branch in Docker:

```bash
.xgc2/scripts/build_runtime_deb_in_docker.sh \
  --work-dir /tmp/px4-runtime-work \
  --output-dir debs
```

For lower-level debugging, run the stages directly:

```bash
.xgc2/scripts/fetch_px4.sh --work-dir /tmp/px4-runtime-work
.xgc2/scripts/build_px4_runtime.sh --px4-dir /tmp/px4-runtime-work/PX4-Autopilot
.xgc2/scripts/extract_px4_runtime.sh \
  --px4-dir /tmp/px4-runtime-work/PX4-Autopilot \
  --output-dir /tmp/px4-runtime-stage
.xgc2/scripts/check_px4_runtime.sh /tmp/px4-runtime-stage
.xgc2/scripts/build_deb.sh \
  --runtime-dir /tmp/px4-runtime-stage \
  --output-dir debs
```

Some branches require an additional Gazebo runtime staging argument; see the
branch scripts and `manifest/px4_runtime.yaml` for the exact branch-specific
build inputs.

## Notes

This repository is a package build and release-preparation wrapper. It is not a
PX4 source fork, not a binary artifact store, and not an APT server. XGC2
production publication remains owned by the central release train; forks must
establish a separate release boundary and must not reuse XGC2 production
credentials.
