[Unit]
Description=mosh session watcher (teardown verdicts, orphan reaper)
Documentation=file://__HOME__/bin/mosh-watch

[Service]
Type=simple
ExecStart=/usr/bin/python3 __HOME__/bin/mosh-watch __HOME__/mosh-watch.log
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=mosh-watch

[Install]
WantedBy=default.target
