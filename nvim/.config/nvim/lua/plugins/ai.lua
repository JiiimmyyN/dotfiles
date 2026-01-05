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
  },
}
