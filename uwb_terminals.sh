#!/usr/bin/env bash
# uwb_launcher.sh
# Usage: ./uwb_launcher.sh -i IP_ADDRESS [-s SETUP_SCRIPT] [--disable-2] [--disable-3]

set -euo pipefail

# --- defaults ---
SSH_USER="administrator"
SETUP_SCRIPT="/home/administrator/marius/uwb_ws/install/setup.bash"
DISABLE2=false
DISABLE3=false

usage() {
  cat <<EOF
Usage: $0 -i IP_ADDRESS [-s SETUP_SCRIPT] [--disable-2] [--disable-3]
  -i IP_ADDRESS     IP or hostname for SSH connections (required)
  -s SETUP_SCRIPT   Absolute path on remote to the ROS2 setup.bash (default: $SETUP_SCRIPT)
  --disable-2       disable the ROS2 launch in session 2 (opens terminal regardless)
  --disable-3       disable the ROS2 launch in session 3 (opens terminal regardless)
  -h, --help        show this help message and exit
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
    -h|--help) usage;;
    *) echo "Unknown argument: $1"; usage;;
  esac
done

: "${IP_ADDRESS:?Error: -i IP_ADDRESS is required}"  # ensure IP_ADDRESS is set

# --- dependency checks ---
for cmd in ssh screen gnome-terminal; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "Error: '$cmd' is required but not installed." >&2
    exit 1
  fi
done

# --- remote: create or restart a screen session ---
remote_start_session() {
  local name="$1"; shift
  local cmds="$*"
  # kill existing remote screen session (ignore errors)
  ssh ${SSH_USER}@${IP_ADDRESS} "screen -S ${name} -X quit" || true
  # start detached screen on remote with specified cmds, then keep shell open
  ssh ${SSH_USER}@${IP_ADDRESS} "screen -dmS ${name} bash -lc '${cmds}; exec bash'"
  echo "Remote screen session '${name}' started on ${IP_ADDRESS}."
}

# --- local: open GNOME Terminal and attach to remote screen ---
open_terminal() {
  local name="$1"
  gnome-terminal \
    --title "${name}@${IP_ADDRESS}" \
    -- bash -ic "ssh -t ${SSH_USER}@${IP_ADDRESS} \
      'screen -r ${name} || echo "Session ${name} ended"; bash --login'"
}

# --- Session 1: always enabled ---
remote_start_session uwb1 \
  "source ${SETUP_SCRIPT} && cd /home/administrator/marius/uwb_ws/src/UWB-Jackal/uwb_scripts/rosbag_recorder"
open_terminal uwb1

echo "Session 1 attached to remote screen 'uwb1'."

# --- Session 2: uwb_shfaf_launch (opens terminal always) ---
remote_start_session uwb2 \
  "source ${SETUP_SCRIPT} && \
   if [ \"${DISABLE2}\" = false ]; then \
     ros2 launch uwb_scripts uwb_shfaf_launch_file.launch.py; \
   else \
     echo 'ros2 launch disabled for session uwb2'; \
   fi"
open_terminal uwb2
if ! $DISABLE2; then
  echo "Session 2: ROS2 launch started in 'uwb2'."
else
  echo "Session 2 terminal opened; ROS2 launch disabled (--disable-2)."
fi

# --- Session 3: uwb_beacons_launch (opens terminal always) ---
remote_start_session uwb3 \
  "source ${SETUP_SCRIPT} && \
   if [ \"${DISABLE3}\" = false ]; then \
     ros2 launch dwm_ros_drivers uwb_beacons_launch_file.launch.py; \
   else \
     echo 'ros2 launch disabled for session uwb3'; \
   fi"
open_terminal uwb3
if ! $DISABLE3; then
  echo "Session 3: ROS2 launch started in 'uwb3'."
else
  echo "Session 3 terminal opened; ROS2 launch disabled (--disable-3)."
fi

echo "All requested sessions set up and terminals opened."
