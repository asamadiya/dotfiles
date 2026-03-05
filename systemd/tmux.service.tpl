[Unit]
Description=tmux default session
After=network.target

[Service]
Type=forking
Environment="USER=__USER__"
Environment="LOGNAME=__USER__"
Environment="HOME=__HOME__"
Environment="SHELL=/bin/bash"
ExecStart=/bin/bash --login -c '__HOME__/.local/bin/tmux new-session -d -s main'
ExecStop=__HOME__/.local/bin/tmux kill-server
RemainAfterExit=yes

[Install]
WantedBy=default.target
