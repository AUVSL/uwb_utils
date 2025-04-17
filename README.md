# uwb_utils
helper script to help launch the necessary stuff


# uwb_terminals.sh
Usage: 
```shell
./uwb_terminals -i IP_ADDRESS [-s SETUP_SCRIPT] [--disable-2] [--disable-3]
```
Command arguments:
```shell
  -i IP_ADDRESS     IP or hostname for SSH connections (required)
  -s SETUP_SCRIPT   Absolute path on remote to the ROS2 setup.bash (default: $SETUP_SCRIPT)
  --disable-2       disable the ROS2 launch in session 2 (opens terminal regardless)
  --disable-3       disable the ROS2 launch in session 3 (opens terminal regardless)
  -h, --help        show this help message and exit
  ```