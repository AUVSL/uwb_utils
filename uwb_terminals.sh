#!/usr/bin/env bash
# uwb_launcher.sh
# Usage: ./uwb_launcher.sh -i IP_ADDRESS [-s SETUP_SCRIPT] [--disable-2] [--disable-3] [--terminate]

set -euo pipefail

# --- defaults ---
SSH_USER="administrator"
SSH_PASS="clearpath"
SETUP_SCRIPT="/home/administrator/marius/uwb_ws/install/setup.bash"
DISABLE2=false
DISABLE3=false
TERMINATE=false

usage() {
  cat <<EOF
Usage: $0 -i IP_ADDRESS [-s SETUP_SCRIPT] [--disable-2] [--disable-3] [--terminate]
  -i IP_ADDRESS     IP or hostname for SSH connections (required)
  -s SETUP_SCRIPT   Absolute path on remote to the ROS2 setup.bash (default: $SETUP_SCRIPT)
  --disable-2       Disable the ROS2 launch in session 2 (opens terminal regardless)
  --disable-3       Disable the ROS2 launch in session 3 (opens terminal regardless)
  --terminate       Kill all remote screen sessions and exit
  -h, --help        Show this help message and exit
EOF
  exit 1
}

# --- parse args ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    -i) IP_ADDRESS="$2"; shift 2;;
    -s) SETUP_SCRIPT="$2"; shift 2;;
    --disable-2) DISABLE2=true; shift;;
    --disable-3) DISABLE3=true; shift;;
    --terminate) TERMINATE=true; shift;;
    -h|--help) usage;;
    *) echo "Unknown argument: $1"; usage;;
  esac
done
: "${IP_ADDRESS:?Error: -i IP_ADDRESS is required}"

# --- dependency checks ---
for cmd in sshpass screen gnome-terminal; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "Error: '$cmd' is required but not installed." >&2; exit 1
  fi
done

# --- SSH command wrapper ---
ssh_cmd() {
  # usage: ssh_cmd remote_host remote_command
  sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "${SSH_USER}@${IP_ADDRESS}" "$1"
}

# --- terminate remote screens ---
if $TERMINATE; then
  echo "Terminating all remote screen sessions..."
  sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "${SSH_USER}@${IP_ADDRESS}" "pkill screen" || true
  echo "All remote screen sessions terminated."
  exit 0
fi

# --- check if remote screen exists ---
screen_exists() {
  sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "${SSH_USER}@${IP_ADDRESS}" \
    "screen -ls | grep -E '^[[:space:]]*[0-9]+\.${1}[[:space:]]'" >/dev/null 2>&1
}

# --- start remote screen if missing ---
remote_start_session() {
  local name="$1"; shift
  local cmd="$*"
  if screen_exists "$name"; then
    echo "[INFO] Remote screen '$name' already exists. Skipping start."
  else
    echo "[INFO] Starting remote screen '$name'..."
    sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "${SSH_USER}@${IP_ADDRESS}" \
      "screen -dmS ${name} bash -lc 'echo "${SSH_PASS}" | sudo -S true; source "${SETUP_SCRIPT}"; ${cmd}; exec bash'"
  fi
}

# --- open local terminal to attach remote screen ---
open_terminal() {
  local name="$1"
  echo "[INFO] Opening terminal for '$name'..."
  gnome-terminal --title "${name}@${IP_ADDRESS}" -- bash -ic "sshpass -p '${SSH_PASS}' ssh -tt -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${SSH_USER}@${IP_ADDRESS} 'screen -x ${name} || screen -r ${name}'; exec bash"
}

# --- Session 1 ---
remote_start_session uwb1 "cd /home/administrator/marius/uwb_ws/src/UWB-Jackal/uwb_scripts/rosbag_recorder"
open_terminal uwb1

# --- Session 2 ---
if ! $DISABLE2; then
  remote_start_session uwb2 "ros2 launch uwb_scripts uwb_shfaf_launch_file.launch.py"
else
  remote_start_session uwb2 "echo 'ROS2 launch disabled for session uwb2'"
fi
open_terminal uwb2

# --- Session 3 ---
if ! $DISABLE3; then
  remote_start_session uwb3 "ros2 launch dwm_ros_drivers uwb_beacons_launch_file.launch.py"
else
  remote_start_session uwb3 "echo 'ROS2 launch disabled for session uwb3'"
fi
open_terminal uwb3

echo "All requested sessions are live and terminals opened."
