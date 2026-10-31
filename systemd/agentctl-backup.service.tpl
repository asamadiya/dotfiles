[Unit]
Description=agentctl: incremental backup of Claude/Copilot transcripts
Documentation=file://__HOME__/my_stuff/dotfiles/bin/agentctl

[Service]
Type=oneshot
ExecStart=/usr/bin/python3 __HOME__/bin/agentctl backup --quiet
Nice=19
IOSchedulingClass=idle
CPUSchedulingPolicy=batch
TimeoutStartSec=30min
