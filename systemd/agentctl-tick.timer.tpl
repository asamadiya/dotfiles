[Unit]
Description=agentctl tick every minute (and right after the user manager starts)

[Timer]
OnActiveSec=20s
OnUnitActiveSec=1min
AccuracySec=10s

[Install]
WantedBy=timers.target
