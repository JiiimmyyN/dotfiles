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
  {
    "hrsh7th/nvim-cmp",
    dependencies = {
      "hrsh7th/cmp-nvim-lsp",
      "hrsh7th/cmp-buffer",
      "hrsh7th/cmp-path",
    },
  },
  {
    "ThePrimeagen/99",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "hrsh7th/nvim-cmp",
    },
    config = function()
      local _99 = require("99")

      local cwd = vim.uv.cwd()
      local basename = vim.fs.basename(cwd)
      _99.setup({
        model = "github-copilot/claude-sonnet-4.5",
        logger = {
          level = _99.DEBUG,
          path = "/tmp/" .. basename .. ".99.debug",
          print_on_error = true,
        },

        completion = {
          --- Defaults to .cursor/rules
          -- I am going to disable these until i understand the
          -- problem better.  Inside of cursor rules there is also
          -- application rules, which means i need to apply these
          -- differently
          -- cursor_rules = "<custom path to cursor rules>"

          --- A list of folders where you have your own SKILL.md
          --- Expected format:
          --- /path/to/dir/<skill_name>/SKILL.md
          ---
          --- Example:
          --- Input Path:
          --- "scratch/custom_rules/"
          ---
          --- Output Rules:
          --- {path = "scratch/custom_rules/vim/SKILL.md", name = "vim"},
          --- ... the other rules in that dir ...
          ---
          custom_rules = {
            "scratch/custom_rules/",
          },

          --- What autocomplete do you use.  We currently only
          --- support cmp right now
          source = "cmp",
        },

        md_files = {
          "AGENT.md",
        },
      })

      vim.keymap.set("n", "<leader>9f", function()
        _99.fill_in_function()
      end)
      -- take extra note that i have visual selection only in v mode
      -- technically whatever your last visual selection is, will be used
      -- so i have this set to visual mode so i dont screw up and use an
      -- old visual selection
      --
      -- likely ill add a mode check and assert on required visual mode
      -- so just prepare for it now
      vim.keymap.set("v", "<leader>av", function()
        _99.visual()
      end)

      --- if you have a request you dont want to make any changes, just cancel it
      vim.keymap.set("v", "<leader>9s", function()
        _99.stop_all_requests()
      end)

      --- Example: Using rules + actions for custom behaviors
      --- Create a rule file like ~/.rules/debug.md that defines custom behavior.
      --- For instance, a "debug" rule could automatically add printf statements
      --- throughout a function to help debug its execution flow.
      vim.keymap.set("n", "<leader>af", function()
        vim.ui.input({ prompt = "Additional prompt: " }, function(input)
          if input then
            _99.fill_in_function({
              additional_prompt = input,
            })
          end
        end)
      end)
    end,
  },
}
