# 30-opts.zsh — zsh shell options.

setopt AUTO_CD                   # `dirname` alone -> cd dirname
setopt EXTENDED_GLOB             # ^ ~ # glob qualifiers on
setopt GLOB_DOTS                 # * matches dotfiles too
setopt INTERACTIVE_COMMENTS      # # in interactive commands
setopt LONG_LIST_JOBS            # full jobs output
setopt NO_BEEP                   # no beep on error
setopt NOTIFY                    # background job status reported immediately
setopt PROMPT_SUBST              # parameter expansion / arithmetic / cmdsub in prompt
setopt NUMERIC_GLOB_SORT         # `ls *.jpg` sorts numerically if applicable

# Vi mode (built-in, no plugin per spec §4.3)
bindkey -v
export KEYTIMEOUT=1              # 10ms escape-to-normal-mode delay
