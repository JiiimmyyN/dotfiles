-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- Diagnostic keymaps
vim.keymap.set("n", "[d", function()
  vim.diagnostic.jump({ count = -1, float = true })
end, { desc = "Go to previous [D]iagnostics message" })
vim.keymap.set("n", "]d", function()
  vim.diagnostic.jump({ count = 1, float = true })
end, { desc = "Go to next [D]iagnostics message" })
vim.keymap.set("n", "<leader>e", function()
  vim.diagnostic.setqflist({ severity = vim.diagnostic.severity.ERROR })
  vim.cmd("copen")
end, { desc = "Show diagnostics [E]rror messages" })
vim.keymap.set("n", "<leader>q", vim.diagnostic.setloclist, { desc = "Open diagnostic [Q]uickfix list" })

------------- CODE FOLING -------------------
------------- Stopped working for some reason -------------------

-- Using treesitter folds
-- vim.o.foldmethod = "expr"
-- vim.o.foldexpr = "nvim_treesitter#foldexpr()"
-- vim.o.foldlevelstart = 99 -- open all folds by default
-- vim.o.foldenable = true
vim.keymap.set("n", "<C-Space>", "za", { noremap = true, silent = true, desc = "Toggle fold" })
---------------------------------------------

------------ Comment out code section ------------

local function feed(keys, mode)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), mode, false)
end

vim.keymap.set("n", "<C-k>c", function()
  feed("gcc", "n")
end, { desc = "Comment line" })

vim.keymap.set("v", "<C-k>c", function()
  feed("gc", "v")
end, { desc = "Comment selection (smart)" })

vim.keymap.set("v", "<C-k>u", function()
  feed("gc", "v")
end, { desc = "Comment selection (smart)" })

---------------------------------------------
