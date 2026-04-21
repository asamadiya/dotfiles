return {
  {
    "stevearc/conform.nvim",
    -- event = 'BufWritePre', -- uncomment for format on save
    opts = require "configs.conform",
  },

  {
    "neovim/nvim-lspconfig",
    config = function()
      require "configs.lspconfig"
    end,
  },

  -- User additions (productivity phase) ------------------------------------
  { "catppuccin/nvim", name = "catppuccin" },
  {
    "lewis6991/gitsigns.nvim",
    event = { "BufReadPre", "BufNewFile" },
    opts = { current_line_blame = false },
  },
  {
    "kdheepak/lazygit.nvim",
    cmd = { "LazyGit", "LazyGitCurrentFile" },
    dependencies = { "nvim-lua/plenary.nvim" },
  },
  { "stevearc/oil.nvim", opts = {} },
  {
    "folke/trouble.nvim",
    cmd = { "Trouble" },
    opts = { use_diagnostic_signs = true },
  },
  {
    "folke/flash.nvim",
    event = "VeryLazy",
    opts = {},
    keys = {
      { "s", mode = { "n", "x", "o" }, function() require("flash").jump() end, desc = "Flash" },
    },
  },
  { "kylechui/nvim-surround", event = "VeryLazy", opts = {} },
  {
    "williamboman/mason.nvim",
    opts = {
      ensure_installed = {
        "lua-language-server", "pyright", "rust-analyzer", "gopls",
        "bash-language-server", "yaml-language-server", "json-lsp",
        "marksman",
      },
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
}
