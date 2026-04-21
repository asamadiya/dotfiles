[Unit]
Description=Hourly state-repo snapshot (commit-only, no push)
After=default.target

[Service]
Type=oneshot
ExecStart=__HOME__/bin/state-snapshot.sh
Environment=HOME=__HOME__
