return {
  "ThePrimeagen/harpoon",
  branch = "harpoon2",
  dependencies = { "nvim-lua/plenary.nvim" },
  opts = {
    settings = {
      save_on_toggle = true,
    },
  },
  keys = function()
    local harpoon = require("harpoon")

    local keys = {
      {
        "<leader>h",
        function()
          harpoon:list():add()
        end,
        desc = "Add to harpoon",
      },
      {
        "<leader>H",
        function()
          harpoon.ui:toggle_quick_menu(harpoon:list())
        end,
        desc = "harpoon menu",
      },
    }

    return keys
  end,
}
