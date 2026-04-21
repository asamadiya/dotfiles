[Unit]
Description=Hourly state-repo snapshot timer

[Timer]
OnCalendar=hourly
Persistent=true

[Install]
WantedBy=timers.target
