[Unit]
Description=agentctl transcript backup every 15 minutes

[Timer]
OnActiveSec=3min
OnUnitActiveSec=15min
RandomizedDelaySec=60s

[Install]
WantedBy=timers.target
