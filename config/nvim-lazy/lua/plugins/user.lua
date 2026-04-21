-- User overrides on top of LazyVim defaults.
return {
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "catppuccin-mocha",
    },
  },
  { "catppuccin/nvim", name = "catppuccin" },
  {
    "kdheepak/lazygit.nvim",
    cmd = { "LazyGit", "LazyGitCurrentFile" },
    dependencies = { "nvim-lua/plenary.nvim" },
    keys = {
      { "<leader>gg", "<cmd>LazyGit<cr>", desc = "Lazygit" },
    },
  },
  {
    "nvim-treesitter/nvim-treesitter",
    opts = {
      ensure_installed = {
        "lua", "python", "rust", "go", "bash", "yaml", "json",
        "markdown", "markdown_inline", "toml", "tmux", "gitcommit",
        "diff", "dockerfile", "make", "regex", "vim", "vimdoc",
      },
    },
  },
  {
    "williamboman/mason.nvim",
    opts = {
      ensure_installed = {
        "pyright", "rust-analyzer", "gopls", "lua-language-server",
        "bash-language-server", "yaml-language-server", "json-lsp",
        "marksman",
      },
    },
  },
}
