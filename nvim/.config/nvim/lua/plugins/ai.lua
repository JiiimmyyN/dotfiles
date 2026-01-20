return {
  {
    "NickvanDyke/opencode.nvim", -- AI Code Completion
    dependencies = {
      { "folke/snacks.nvim", opts = { input = {}, picker = {}, terminal = {} } },
    },
    config = function()
      vim.g.opencode_opts = {}

      vim.o.autoread = true

      vim.keymap.set({ "n", "x" }, "<leader>ao", function()
        require("opencode").ask("@this: ", { submit = true })
      end, { desc = "Ask opencode" })
      vim.keymap.set({ "n", "x" }, "<leader>at", function()
        require("opencode").select()
      end, { desc = "Toggle Opencode" })
      vim.keymap.set({ "n", "x" }, "<C-,>", function()
        require("opencode").toggle()
      end, { desc = "Toggle Opencode" })
    end,
  },
  {
    "github/copilot.vim",
    init = function()
      vim.g.copilot_no_tab_map = true
      vim.g.copilot_assume_mapped = true
    end,
    config = function()
      vim.keymap.set("i", "<C-l>", "<Plug>(copilot-accept-line)", { silent = true })
      vim.keymap.set("i", "<Tab>", "<Plug>(copilot-accept-line)", { silent = true })

      -- optional: cycle suggestions
      vim.keymap.set("i", "<M-]>", "<Plug>(copilot-next)", { silent = true })
      vim.keymap.set("i", "<M-[>", "<Plug>(copilot-previous)", { silent = true })

      -- optional: dismiss
      vim.keymap.set("i", "<C-]>", "<Plug>(copilot-dismiss)", { silent = true })
    end,
  },
}
