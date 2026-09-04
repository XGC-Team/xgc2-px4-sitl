#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

RUNTIME_ROOT="${PX4_SITL_RUNTIME_ROOT:-}"
GAZEBO_ROOT="${SITL_GAZEBO_CLASSIC_ROOT:-}"
WORK_DIR="${PX4_SITL_WORK_DIR:-/tmp/px4_sitl_e2e}"
MODEL="${PX4_SIM_MODEL:-iris}"
TIMEOUT_S="${PX4_E2E_TIMEOUT_S:-90}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --runtime-root)
      RUNTIME_ROOT="$2"
      shift 2
      ;;
    --gazebo-root)
      GAZEBO_ROOT="$2"
      shift 2
      ;;
    --work-dir)
      WORK_DIR="$2"
      shift 2
      ;;
    --model)
      MODEL="$2"
      shift 2
      ;;
    --timeout)
      TIMEOUT_S="$2"
      shift 2
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "${RUNTIME_ROOT}" || ! -x "${RUNTIME_ROOT}/bin/px4" ]]; then
  echo "--runtime-root is required and must contain bin/px4" >&2
  exit 1
fi

if [[ -z "${GAZEBO_ROOT}" || ! -d "${GAZEBO_ROOT}/models" || ! -d "${GAZEBO_ROOT}/lib" ]]; then
  echo "--gazebo-root is required and must contain models and lib" >&2
  exit 1
fi

test -f "${GAZEBO_ROOT}/worlds/empty.world"
test -f "${GAZEBO_ROOT}/models/${MODEL}/${MODEL}.sdf"

# shellcheck disable=SC1091
set +u
source /opt/ros/noetic/setup.bash
set -u

LOG_DIR="$(mktemp -d)"
PIDS=()

cleanup() {
  local status=$?
  for pid in "${PIDS[@]}"; do
    kill "${pid}" >/dev/null 2>&1 || true
  done
  wait >/dev/null 2>&1 || true
  if [[ "${status}" -ne 0 ]]; then
    echo "E2E check failed; logs are in ${LOG_DIR}" >&2
    for log in roscore.log gzserver.log px4.log mavros.log; do
      if [[ -f "${LOG_DIR}/${log}" ]]; then
        echo "---- ${log} ----" >&2
        tail -n 120 "${LOG_DIR}/${log}" >&2 || true
      fi
    done
  else
    rm -rf "${LOG_DIR}"
  fi
  exit "${status}"
}
trap cleanup EXIT INT TERM

rm -rf "${WORK_DIR}"
mkdir -p "${WORK_DIR}"

export PX4_SIM_MODEL="${MODEL}"
export PX4_SIM_HOSTNAME=localhost
export GAZEBO_PLUGIN_PATH="${GAZEBO_ROOT}/lib:${GAZEBO_PLUGIN_PATH:-}"
export GAZEBO_MODEL_PATH="${GAZEBO_ROOT}/models:${GAZEBO_MODEL_PATH:-}"
export LD_LIBRARY_PATH="${GAZEBO_ROOT}/lib:${LD_LIBRARY_PATH:-}"

roscore >"${LOG_DIR}/roscore.log" 2>&1 &
PIDS+=("$!")

deadline=$((SECONDS + TIMEOUT_S))
until rosnode list >/dev/null 2>&1; do
  if (( SECONDS >= deadline )); then
    echo "timed out waiting for roscore" >&2
    exit 1
  fi
  sleep 1
done

gzserver --verbose "${GAZEBO_ROOT}/worlds/empty.world" >"${LOG_DIR}/gzserver.log" 2>&1 &
PIDS+=("$!")

deadline=$((SECONDS + TIMEOUT_S))
until gz model --list >/dev/null 2>&1; do
  if (( SECONDS >= deadline )); then
    echo "timed out waiting for gzserver" >&2
    exit 1
  fi
  sleep 1
done

"${REPO_ROOT}/scripts/run_px4_sitl.sh" \
  --runtime-root "${RUNTIME_ROOT}" \
  --work-dir "${WORK_DIR}" \
  --instance 0 \
  -- -d >"${LOG_DIR}/px4.log" 2>&1 &
PIDS+=("$!")

deadline=$((SECONDS + TIMEOUT_S))
until grep -q "Waiting for simulator to connect" "${LOG_DIR}/px4.log"; do
  if grep -Eq "Error: Unknown model|Startup script returned with return value" "${LOG_DIR}/px4.log"; then
    echo "PX4 failed before Gazebo connection" >&2
    exit 1
  fi
  if (( SECONDS >= deadline )); then
    echo "timed out waiting for PX4 simulator startup" >&2
    exit 1
  fi
  sleep 1
done

deadline=$((SECONDS + TIMEOUT_S))
until gz model --spawn-file="${GAZEBO_ROOT}/models/${MODEL}/${MODEL}.sdf" --model-name="${MODEL}" -z 0.83 >/dev/null 2>&1; do
  if (( SECONDS >= deadline )); then
    echo "timed out spawning ${MODEL}" >&2
    exit 1
  fi
  sleep 1
done

deadline=$((SECONDS + TIMEOUT_S))
until grep -q "Startup script returned successfully" "${LOG_DIR}/px4.log"; do
  if grep -Eq "Startup script returned with return value|Error:" "${LOG_DIR}/px4.log"; then
    echo "PX4 startup failed" >&2
    exit 1
  fi
  if (( SECONDS >= deadline )); then
    echo "timed out waiting for PX4 startup success" >&2
    exit 1
  fi
  sleep 1
done

roslaunch mavros px4.launch fcu_url:=udp://:15000@localhost:15300 gcs_url:= >"${LOG_DIR}/mavros.log" 2>&1 &
PIDS+=("$!")

deadline=$((SECONDS + TIMEOUT_S))
until rostopic echo -n1 /mavros/state 2>/dev/null | grep -q "connected: True"; do
  if (( SECONDS >= deadline )); then
    echo "timed out waiting for MAVROS FCU connection" >&2
    exit 1
  fi
  sleep 1
done

echo "Gazebo Classic + PX4 SITL + MAVROS E2E check passed"
