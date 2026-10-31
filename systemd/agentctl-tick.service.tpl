[Unit]
Description=agentctl: snapshot tmux + agent sessions, restore after tmux loss or reboot
Documentation=file://__HOME__/my_stuff/dotfiles/bin/agentctl

[Service]
Type=oneshot
# Restores start the tmux server in its own transient scope (systemd-run --scope),
# so it survives this oneshot. KillMode=process is a second guard for anything else
# this unit forks.
KillMode=process
ExecStart=/usr/bin/python3 __HOME__/bin/agentctl tick
TimeoutStartSec=5min
Nice=5
