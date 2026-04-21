# : << 'EOF'
# ~/.tmux.conf.local — __USER__'s overrides for oh-my-tmux
# Power user / terminal native config


# -- bindings ------------------------------------------------------------------

tmux_conf_preserve_stock_bindings=false


# -- session creation ----------------------------------------------------------

tmux_conf_new_session_prompt=false
tmux_conf_new_session_retain_current_path=true


# -- windows & pane creation ---------------------------------------------------

tmux_conf_new_window_retain_current_path=true
tmux_conf_new_window_reconnect_ssh=true
tmux_conf_new_pane_retain_current_path=true
tmux_conf_new_pane_reconnect_ssh=true


# -- display -------------------------------------------------------------------

tmux_conf_24b_colour=auto


# -- theming: Catppuccin Mocha-inspired dark theme ----------------------------

tmux_conf_theme=enabled

tmux_conf_theme_colour_1="#1e1e2e"    # base (dark bg)
tmux_conf_theme_colour_2="#313244"    # surface0
tmux_conf_theme_colour_3="#a6adc8"    # subtext0
tmux_conf_theme_colour_4="#89b4fa"    # blue
tmux_conf_theme_colour_5="#f9e2af"    # yellow
tmux_conf_theme_colour_6="#1e1e2e"    # base
tmux_conf_theme_colour_7="#cdd6f4"    # text
tmux_conf_theme_colour_8="#1e1e2e"    # base
tmux_conf_theme_colour_9="#f9e2af"    # yellow
tmux_conf_theme_colour_10="#cba6f7"   # mauve
tmux_conf_theme_colour_11="#a6e3a1"   # green
tmux_conf_theme_colour_12="#a6adc8"   # subtext0
tmux_conf_theme_colour_13="#cdd6f4"   # text
tmux_conf_theme_colour_14="#1e1e2e"   # base
tmux_conf_theme_colour_15="#1e1e2e"   # base
tmux_conf_theme_colour_16="#f38ba8"   # red
tmux_conf_theme_colour_17="#cdd6f4"   # text

tmux_conf_theme_highlight_focused_pane=true
tmux_conf_theme_focused_pane_bg="$tmux_conf_theme_colour_1"
tmux_conf_theme_pane_border_style=thin
tmux_conf_theme_pane_border="$tmux_conf_theme_colour_2"
tmux_conf_theme_pane_active_border="$tmux_conf_theme_colour_4"

# Powerline separators
tmux_conf_theme_left_separator_main='\uE0B0'
tmux_conf_theme_left_separator_sub='\uE0B1'
tmux_conf_theme_right_separator_main='\uE0B2'
tmux_conf_theme_right_separator_sub='\uE0B3'

# Window status format — show zoomed/bell indicators
tmux_conf_theme_window_status_format="#I #W#{?#{||:#{window_bell_flag},#{window_zoomed_flag}}, ,}#{?window_bell_flag,!,}#{?window_zoomed_flag,Z,}"
tmux_conf_theme_window_status_current_format="#I #W#{?#{||:#{window_bell_flag},#{window_zoomed_flag}}, ,}#{?window_bell_flag,!,}#{?window_zoomed_flag,Z,}"

# Status bar content
tmux_conf_theme_status_left=" #S | #{hostname_ssh} "
tmux_conf_theme_status_right=" #{prefix}#{mouse}#{pairing}#{synchronized} #{loadavg} , %R %d-%b | #{username}#{root}@#{hostname} "

# 24h clock
tmux_conf_theme_clock_colour="$tmux_conf_theme_colour_4"
tmux_conf_theme_clock_style="24"

# Terminal title
tmux_conf_theme_terminal_title="#h : #S > #W"


# -- clipboard ----------------------------------------------------------------

tmux_conf_copy_to_os_clipboard=true


# -- user customizations ------------------------------------------------------

# Login shell — prevents "nobody" user in restored panes
set -g default-command "exec /bin/bash --login"
set -g default-shell "/bin/bash"

# Vi mode
set -g mode-keys vi
set -g status-keys vi

# Mouse
set -g mouse on

# Tighter refresh for livelier CPU% + MEM signals in the sysstat segment
set -g status-interval 5

# Explicit OSC 52 propagation so yank-to-clipboard reaches Mac terminal
set -g set-clipboard on

# History
set -g history-limit 50000

# Fast escape (no delay after prefix)
set -sg escape-time 0

# Prefix: C-space
set -gu prefix2
unbind C-a
unbind C-b
set -g prefix C-space
bind C-space send-prefix

# Vi copy mode bindings
bind-key -T copy-mode-vi v send -X begin-selection
bind-key -T copy-mode-vi V send -X select-line
bind-key -T copy-mode-vi y send -X copy-pipe-and-cancel 'xclip -in -selection clipboard'

# Pane splitting
bind | split-window -h -c "#{pane_current_path}" #!important
bind - split-window -v -c "#{pane_current_path}" #!important

# Vim-style pane navigation
bind h select-pane -L #!important
bind j select-pane -D #!important
bind k select-pane -U #!important
bind l select-pane -R #!important

# Pane resizing
bind -r H resize-pane -L 5
bind -r J resize-pane -D 5
bind -r K resize-pane -U 5
bind -r L resize-pane -R 5

# Toggle mouse with m
bind m run "cut -c3- '#{TMUX_CONF}' | sh -s _toggle_mouse" \; display 'mouse #{?#{mouse},on,off}'


# -- tpm & persistence --------------------------------------------------------

tmux_conf_update_plugins_on_launch=true
tmux_conf_update_plugins_on_reload=true

set -g @plugin 'tmux-plugins/tmux-resurrect'
set -g @plugin 'tmux-plugins/tmux-continuum'

# Resurrect: capture everything
set -g @resurrect-capture-pane-contents 'on'
set -g @resurrect-strategy-vim 'session'
set -g @resurrect-strategy-nvim 'session'
set -g @resurrect-processes 'claude->__HOME__/bin/tmux-claude-restore copilot->__HOME__/bin/tmux-copilot-restore ssh vim nvim htop man less tail top watch'
set -g @resurrect-hook-post-save-all '__HOME__/bin/tmux-save-claude-sessions; __HOME__/bin/tmux-save-copilot-sessions'

# Continuum: auto-save every 5 min, auto-restore on tmux start
set -g @continuum-save-interval '5'
set -g @continuum-restore 'on'
set -g @continuum-boot 'on'

# Additional plugins
set -g @plugin 'sainnhe/tmux-fzf'
set -g @plugin 'tmux-plugins/tmux-yank'
set -g @plugin 'Morantron/tmux-fingers'
set -g @plugin 'tmux-plugins/tmux-open'

# tmux-fzf
TMUX_FZF_LAUNCH_KEY="f"
TMUX_FZF_ORDER="session|window|pane|command|keybinding"

# tmux-yank (OSC52 fallback if no xclip)
set -g @yank_selection_mouse 'clipboard'
set -g @yank_action 'copy-pipe'

# tmux-fingers
set -g @fingers-key F
set -g @fingers-pattern-0 '[a-f0-9]{7,40}'
set -g @fingers-pattern-1 'https?://[^\s>)]*'


# -- fixes applied post-setup ------------------------------------------------

# Enable clickable hyperlinks (requires tmux >= 3.4)
set -g allow-passthrough on
set -as terminal-features ",*:hyperlinks"

# Restore prefix+p/n for previous/next window (oh-my-tmux overrides p to paste)
bind p previous-window #!important
bind n next-window #!important

# Mouse: hold Shift to select text normally (bypasses tmux mouse capture)
# MouseDragEnd copies to clipboard automatically
bind-key -T copy-mode-vi MouseDragEnd1Pane send-keys -X copy-pipe-and-cancel 'xclip -in -selection clipboard'

# -- custom variables ----------------------------------------------------------

# >>> sysstat segment (managed) >>>
set-option -ga status-right " #(__HOME__/bin/sysstat.sh)"
# <<< sysstat segment (managed) <<<

# >>> wt keybindings (managed) >>>
bind w   display-popup -E -w 80% -h 60% -d "#{pane_current_path}" "__HOME__/bin/wt jump"
bind W   command-prompt -p "wt add branch:"     "display-popup -E -d '#{pane_current_path}' '__HOME__/bin/wt add %%'"
bind C-c command-prompt -p "wt claude branch:"  "display-popup -E -d '#{pane_current_path}' '__HOME__/bin/wt claude %%'"
bind C-p command-prompt -p "wt copilot branch:" "display-popup -E -d '#{pane_current_path}' '__HOME__/bin/wt copilot %%'"
# <<< wt keybindings (managed) <<<

# >>> pane-logging (managed) >>>
bind L   run-shell "__HOME__/bin/pane-log-toggle.sh"
bind M-L run-shell "__HOME__/bin/pane-log-mode.sh"
# <<< pane-logging (managed) <<<

# /!\ do not remove the following line
# EOF
#
# /!\ do not "uncomment" the functions: the leading "# " characters are needed
#
# usage: #{loadavg}
# loadavg() {
#   cat /proc/loadavg | cut -d' ' -f1-3
# }
#
# usage: #{gpu_util}
# gpu_util() {
#   nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null | head -1 | sed 's/ //g' | awk '{printf "GPU:%s%%", $1}' || printf ''
#   sleep 5
# }
#
# "$@"
# /!\ do not remove the previous line
#     do not write below this line

