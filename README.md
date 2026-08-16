# px4_sitl_runtime

Build rules for the XGC2 PX4 v1.16 SITL Debian package on ROS Jazzy.

This repository does not store PX4 source trees, PX4 binaries, Gazebo Sim assets, or built `.deb` files. CI clones the configured PX4 tag, builds the SITL runtime in the target Ubuntu/ROS environment, extracts the PX4 Gazebo Sim Harmonic model store, and packages only the runtime artifacts users need.

## Package Model

This branch publishes one user-facing Gazebo Sim Harmonic Debian package:

```bash
ros-jazzy-xgc2-gz-harmonic-px4-1-16
```

The build emits a PX4 SITL runtime package and a Gazebo Sim Harmonic package. Installing `ros-jazzy-xgc2-gz-harmonic-px4-1-16` also installs the matching PX4 runtime dependency and provides these ROS 2 packages under `/opt/ros/jazzy`:

```text
px4_sitl_runtime_1_16
px4_gz_sim_1_16
```

`px4_sitl_runtime_1_16` contains the extracted PX4 SITL runtime files and helper scripts. `px4_gz_sim_1_16` contains PX4 v1.16 Gazebo Sim Harmonic models, worlds, `server.config`, and the `simulation-gazebo` helper.

The PX4 maintenance line is encoded in the Debian package name. The Debian `Version` tracks the exact PX4 tag plus a packaging revision:

```text
PX4 v1.16.2 -> ros-jazzy-xgc2-gz-harmonic-px4-1-16 1.16.2-1
PX4 v1.16.2 packaging fix -> ros-jazzy-xgc2-gz-harmonic-px4-1-16 1.16.2-2
```

## User Installation

Once the self-hosted APT repository is enabled, install the runtime with:

```bash
curl -fsSL https://APT_DOMAIN/xgc2-archive-keyring.gpg | \
  sudo gpg --dearmor -o /usr/share/keyrings/xgc2-archive-keyring.gpg

echo "deb [signed-by=/usr/share/keyrings/xgc2-archive-keyring.gpg arch=amd64] https://APT_DOMAIN noble main" | \
  sudo tee /etc/apt/sources.list.d/xgc2.list

sudo apt update
sudo apt install ros-jazzy-xgc2-gz-harmonic-px4-1-16
```

Check available packaging revisions:

```bash
apt-cache madison ros-jazzy-xgc2-gz-harmonic-px4-1-16
```

Confirm the ROS 2 packages are discoverable:

```bash
source /opt/ros/jazzy/setup.bash
ros2 pkg prefix px4_sitl_runtime_1_16
ros2 pkg prefix px4_gz_sim_1_16
```

Run the packaged Gazebo Sim helper against the installed model store:

```bash
ros2 run px4_gz_sim_1_16 simulation-gazebo --world default
```

## Installed Layout

PX4 SITL runtime:

```text
/opt/ros/jazzy/share/px4_sitl_runtime_1_16/
├── config/
├── package.xml
└── runtime/
    ├── bin/
    │   ├── px4
    │   ├── px4-alias.sh
    │   └── px4-* -> px4
    ├── etc/
    └── setup.bash

/opt/ros/jazzy/lib/px4_sitl_runtime_1_16/
├── run_px4_sitl.sh
└── setup_runtime_env.sh
```

Gazebo Sim Harmonic runtime:

```text
/opt/ros/jazzy/share/px4_gz_sim_1_16/
├── models/
├── package.xml
├── server.config
├── simulation-gazebo
└── worlds/

/opt/ros/jazzy/lib/px4_gz_sim_1_16/
└── simulation-gazebo
```

## Local Build

The normal local path builds inside the versioned XGC2 Noble/Jazzy full build
image:

```bash
.xgc2/scripts/build_runtime_deb_in_docker.sh \
  --work-dir /tmp/px4-runtime-work \
  --output-dir debs
```

The script pulls
`ghcr.io/xgc-team/xgc2-images/xgc2-build-noble-full-jazzy:1.0.0`,
clones the pinned PX4 v1.16.2 source, initializes PX4 submodules, installs its
additional build-only dependencies and runs the setup script shipped by that
pinned source inside the disposable container. It then builds
`px4_sitl_default`, extracts PX4 runtime files and Gazebo Sim Harmonic assets,
builds the Debian package, installs that local package, and verifies all three
ROS 2 packages with `ros2 pkg prefix`.

For lower-level debugging, run the stages directly:

```bash
.xgc2/scripts/fetch_px4.sh --work-dir /tmp/px4-runtime-work
.xgc2/scripts/build_px4_runtime.sh --px4-dir /tmp/px4-runtime-work/PX4-Autopilot
.xgc2/scripts/extract_px4_runtime.sh \
  --px4-dir /tmp/px4-runtime-work/PX4-Autopilot \
  --output-dir /tmp/px4-runtime-stage
.xgc2/scripts/extract_gz_sim_runtime.sh \
  --px4-dir /tmp/px4-runtime-work/PX4-Autopilot \
  --output-dir /tmp/gz-sim-runtime-stage
.xgc2/scripts/check_px4_runtime.sh /tmp/px4-runtime-stage
.xgc2/scripts/check_gz_sim_runtime.sh /tmp/gz-sim-runtime-stage
.xgc2/scripts/build_deb.sh \
  --runtime-dir /tmp/px4-runtime-stage \
  --gz-sim-dir /tmp/gz-sim-runtime-stage \
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
3. Pulls the versioned XGC2 Noble/Jazzy full build image.
4. Runs the full build inside a disposable Docker container.
5. Clones PX4-Autopilot at the configured tag and initializes all PX4 submodules.
6. Runs the pinned PX4 source's Ubuntu dependency setup inside the disposable
   build container.
7. Builds `px4_sitl_default`.
8. Extracts PX4 runtime files and `Tools/simulation/gz`.
9. Builds `ros-jazzy-xgc2-px4-sitl-1-16` and `ros-jazzy-xgc2-gz-harmonic-px4-1-16`.
10. Installs the local `.deb` inside the container.
11. Checks `px4_sitl_runtime_1_16` and `px4_gz_sim_1_16` with `ros2 pkg prefix`.
12. Uploads the `.deb` and build manifest as workflow artifacts named by Debian
    architecture.
13. Returns those trusted artifacts to the central release train for staging
    and atomic promotion; this product workflow does not hold production APT
    credentials or publish directly.
