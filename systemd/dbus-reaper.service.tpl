[Unit]
Description=Reap orphan session dbus-daemons leaked by authn-cli
Documentation=file://__HOME__/my_stuff/dotfiles/shell/shared.sh

[Service]
Type=simple
ExecStart=/bin/sh -c 'while :; do pkill -U %U -x --older 300 dbus-daemon; sleep 60; done'
Restart=always
RestartSec=5
SyslogIdentifier=dbus-reaper

[Install]
WantedBy=default.target
