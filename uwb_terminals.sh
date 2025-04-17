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
  --terminate       Kill existing screen sessions and close related gnome-terminals
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
    echo "Error: '$cmd' is required but not installed." >&2
    exit 1
  fi
done

# SSH wrapper to avoid repeated password prompts
ssh_cmd() {
  sshpass -p "${SSH_PASS}" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$@"
}

# --- terminate previous screen and terminal sessions ---
if $TERMINATE; then
  echo "Terminating previous screen sessions and gnome terminals..."
  # kill remote screen sessions uwb1, uwb2, uwb3
  ssh_cmd ${SSH_USER}@${IP_ADDRESS} "screen -ls | awk '/uwb[123]/ {print \$1}' | xargs -r -n1 screen -S {} -X quit"
  # kill local gnome-terminal windows with our titles
  pkill -f "uwb[123]@${IP_ADDRESS}" || true
  echo "All previous sessions terminated."
  exit 0
fi

# --- remote: start screen session only if not already running ---
remote_start_session() {
  local name="$1"; shift
  local init_cmds="$*"

  # skip if session already exists
  if ssh_cmd ${SSH_USER}@${IP_ADDRESS} "screen -list | grep -q '[[:space:]]${name}[[:space:]]'"; then
    echo "Remote screen session '${name}' already running."
  else
    local remote_script="/tmp/init_${name}_$$.sh"
    # prepare remote init script: sudo, source, commands, interactive shell
    local content="echo '${SSH_PASS}' | sudo -S true; source ${SETUP_SCRIPT}; ${init_cmds}; exec bash"

    ssh_cmd ${SSH_USER}@${IP_ADDRESS} "echo '${content}' > ${remote_script} && chmod +x ${remote_script}"
    ssh_cmd ${SSH_USER}@${IP_ADDRESS} "screen -dmS ${name} bash -c '${remote_script}'"

    echo "Remote screen session '${name}' started."
  fi
}

# --- local: open GNOME Terminal and attach to remote screen ---
open_terminal() {
  local name="$1"
  gnome-terminal \
    --title "${name}@${IP_ADDRESS}" \
    -- bash -ic "sshpass -p '${SSH_PASS}' ssh -tt -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${SSH_USER}@${IP_ADDRESS} 'screen -r ${name}' || bash; exec bash"
}

# --- Session 1 ---
remote_start_session uwb1 \
  "cd /home/administrator/marius/uwb_ws/src/UWB-Jackal/uwb_scripts/rosbag_recorder"
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


echo "All requested sessions launched and interactive terminals opened."