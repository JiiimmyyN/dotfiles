return {
  -- This makes Lazy load your local lua module as a “plugin”
  dir = vim.fn.stdpath("config") .. "/lua/supersearch",
  name = "supersearch",
  dependencies = { "nvim-telescope/telescope.nvim" },
  lazy = true,
  keys = {
    {
      "<C-p>",
      function()
        require("supersearch").open()
      end,
      desc = "SuperSearch",
    },
  },
}
