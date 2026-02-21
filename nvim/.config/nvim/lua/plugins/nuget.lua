return {
  dir = vim.fn.stdpath("config") .. "/lua/nuget",
  name = "nuget",
  lazy = true,
  cmd = { "Nuget" },
  keys = {
    { "<leader>cn", function() require("nuget").open() end, desc = "NuGet Package Manager" },
  },
  opts = {},
  config = function(_, opts)
    require("nuget").setup(opts)
  end,
}
