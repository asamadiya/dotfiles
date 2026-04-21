require "nvchad.mappings"

local map = vim.keymap.set

-- NvChad starter defaults
map("n", ";", ":", { desc = "CMD enter command mode" })
map("i", "jk", "<ESC>")

-- User additions (productivity phase) ---------------------------------------
map("n", "<leader>ff", "<cmd>Telescope find_files<cr>", { desc = "Find files" })
map("n", "<leader>fg", "<cmd>Telescope live_grep<cr>",  { desc = "Live grep" })
map("n", "<leader>fb", "<cmd>Telescope buffers<cr>",    { desc = "Buffers" })
map("n", "<leader>fk", "<cmd>Telescope keymaps<cr>",    { desc = "Keymaps" })
map("n", "<leader>gg", "<cmd>LazyGit<cr>",              { desc = "Lazygit" })
map("n", "<leader>gs", "<cmd>Gitsigns toggle_current_line_blame<cr>", { desc = "Git blame toggle" })
map("n", "<leader>gd", "<cmd>Gitsigns preview_hunk<cr>",{ desc = "Git preview hunk" })
map("n", "<leader>xx", "<cmd>Trouble diagnostics toggle<cr>", { desc = "Trouble diagnostics" })
map("n", "<leader>e",  "<cmd>Oil --float<cr>",          { desc = "File manager" })
