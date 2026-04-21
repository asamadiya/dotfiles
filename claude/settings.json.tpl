{
  "enabledPlugins": {
    "superpowers@claude-plugins-official": true,
    "code-review@claude-plugins-official": true,
    "github@claude-plugins-official": true,
    "feature-dev@claude-plugins-official": true,
    "commit-commands@claude-plugins-official": true,
    "claude-md-management@claude-plugins-official": true,
    "pr-review-toolkit@claude-plugins-official": true,
    "claude-code-setup@claude-plugins-official": true,
    "skill-creator@claude-plugins-official": true
  },
  "skipDangerousModePermissionPrompt": true,
  "model": "opus[1m]",
  "permissions": {
    "allow": [
      "Bash(git *)",
      "Bash(rg *)",
      "Bash(fd *)",
      "Bash(ls *)",
      "Bash(cat *)",
      "Bash(head *)",
      "Bash(tail *)",
      "Bash(wc *)",
      "Bash(diff *)",
      "Bash(jq *)",
      "Bash(python3 *)",
      "Bash(pip3 *)",
      "Bash(pip *)",
      "Bash(curl *)",
      "Bash(which *)",
      "Bash(ps *)",
      "Bash(pgrep *)",
      "Bash(pkill *)",
      "Bash(tmux *)",
      "Bash(nvidia-smi *)",
      "Bash(systemctl --user *)",
      "Bash(chmod *)",
      "Bash(mkdir *)",
      "Bash(cp *)",
      "Bash(mv *)",
      "Bash(ln *)",
      "Bash(touch *)",
      "Bash(pytest *)",
      "Bash(make *)",
      "Bash(docker *)",
      "Bash(kubectl *)",
      "Bash(mint *)",
      "Bash(gh *)",
      "Bash(ssh *)",
      "Bash(scp *)",
      "Bash(htop)",
      "Bash(free *)",
      "Bash(df *)",
      "Bash(du *)",
      "Bash(env)",
      "Bash(printenv *)",
      "Bash(whoami)",
      "Bash(hostname)",
      "Bash(uptime)",
      "Bash(id)",
      "Read",
      "Write",
      "Edit",
      "Glob",
      "Grep",
      "Agent",
      "WebFetch",
      "WebSearch",
      "NotebookEdit"
    ],
    "deny": [
      "Bash(rm -rf /)",
      "Bash(rm -rf ~)",
      "Bash(> /dev/sda*)",
      "Read(.env)",
      "Read(.env.*)"
    ]
  },
  "cleanupPeriodDays": 30,
  "spinnerTipsEnabled": false,
  "alwaysThinkingEnabled": true,
  "showThinkingSummaries": true,
  "autoMemoryEnabled": true,
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1",
    "CLAUDE_CODE_MAX_OUTPUT_TOKENS": "64000",
    "CLAUDE_AUTOCOMPACT_PCT_OVERRIDE": "80"
  },
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "node \"__HOME__/.claude/hooks/gsd-check-update.js\""
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "__HOME__/bin/claude-guard-main.sh"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "node \"__HOME__/.claude/hooks/gsd-context-monitor.js\""
          }
        ]
      }
    ],
    "Notification": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "tmux display-message 'Claude Code needs attention' 2>/dev/null; echo '\\a'"
          }
        ]
      }
    ],
    "SessionEnd": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "__HOME__/bin/session-end-autocommit.sh claude ${CLAUDE_CODE_SESSION:-unknown}"
          }
        ]
      }
    ]
  },
  "statusLine": {
    "type": "command",
    "command": "__HOME__/bin/claude-statusline.sh"
  }
}
