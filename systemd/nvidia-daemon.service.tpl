[Unit]
Description=NVIDIA GPU telemetry cache writer (for tmux sysstat segment)
After=default.target

[Service]
Type=simple
ExecStart=__HOME__/bin/nvidia-daemon.sh
Restart=on-failure
RestartSec=10
# Silent exit (no NVIDIA driver) is success; don't restart-loop on that.
SuccessExitStatus=0

[Install]
WantedBy=default.target
