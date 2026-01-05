return {
  {
    "NeogitOrg/neogit",
    lazy = true,
    dependencies = {
      "nvim-lua/plenary.nvim", -- required
      "sindrets/diffview.nvim", -- optional - Diff integration

      -- Only one of these is needed.
      "nvim-telescope/telescope.nvim", -- optional
      --"ibhagwan/fzf-lua",              -- optional
      --"nvim-mini/mini.pick",           -- optional
      --"folke/snacks.nvim",             -- optional
    },
    cmd = "Neogit",
    keys = {
      { "<leader>gn", "<cmd>Neogit<cr>", desc = "Show [N]eogit UI" },
    },
  },
  {
    "ThePrimeagen/git-worktree.nvim", -- Manage git worktrees
    dependencies = {
      "nvim-telescope/telescope.nvim",
    },
    config = function()
      require("git-worktree").setup({
        -- See `:help git-worktree.nvim` for configuration options
      })

      -- Keymap to open the git worktree telescope picker
      vim.keymap.set("n", "<leader>gwt", function()
        require("telescope").extensions.git_worktree.git_worktrees()
      end, { desc = "Git [W]ork[t]rees" })

      vim.keymap.set("n", "<leader>gwc", function()
        require("telescope").extensions.git_worktree.create_git_worktree()
      end, { desc = "Git [C]reate new [W]orktrees" })
    end,
  },
}
