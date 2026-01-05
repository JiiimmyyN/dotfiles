return {
  "ThePrimeagen/harpoon",
  branch = "harpoon2",
  dependencies = { "nvim-lua/plenary.nvim", "nvim-telescope/telescope.nvim" },
  opts = {
    settings = {
      save_on_toggle = true,
    },
  },
  keys = function()
    local harpoon = require("harpoon")

    local conf = require("telescope.config").values
    local function toggle_telescope(harpoon_files)
      local file_paths = {}
      for _, item in ipairs(harpoon_files.items) do
        table.insert(file_paths, item.value)
      end

      require("telescope.pickers")
        .new({}, {
          prompt_title = "Harpoon",
          finder = require("telescope.finders").new_table({
            results = file_paths,
          }),
          previewer = conf.file_previewer({}),
          sorter = conf.generic_sorter({}),
        })
        :find()
    end
    --
    local pickers = require("telescope.pickers")
    local finders = require("telescope.finders")
    local conf = require("telescope.config").values
    local actions = require("telescope.actions")
    local action_state = require("telescope.actions.state")

    local function harpoon_finder(list)
      -- Build entries that keep the harpoon index
      local results = {}
      for i, item in ipairs(list.items) do
        results[#results + 1] = {
          idx = i,
          value = item.value,
          display = item.value,
          ordinal = item.value,
        }
      end

      return finders.new_table({
        results = results,
        entry_maker = function(entry)
          -- telescope expects these fields
          return {
            value = entry.value,
            display = entry.display,
            ordinal = entry.ordinal,
            idx = entry.idx, -- keep harpoon index on the entry
          }
        end,
      })
    end

    local function toggle_telescope_harpoon(list)
      pickers
        .new({}, {
          prompt_title = "Harpoon",
          finder = harpoon_finder(list),
          previewer = conf.file_previewer({}),
          sorter = conf.generic_sorter({}),

          attach_mappings = function(prompt_bufnr, map)
            local function refresh_picker()
              local picker = action_state.get_current_picker(prompt_bufnr)
              picker:refresh(harpoon_finder(list), { reset_prompt = false })
            end

            -- Default: <CR> opens selection
            map("i", "<CR>", function()
              local entry = action_state.get_selected_entry()
              actions.close(prompt_bufnr)
              if entry and entry.value then
                vim.cmd.edit(vim.fn.fnameescape(entry.value))
              end
            end)

            -- Delete selected harpoon mark
            -- Choose your key: <C-d>, <M-d>, "dd", etc.
            map({ "i", "n" }, "<C-d>", function()
              local entry = action_state.get_selected_entry()
              if not entry then
                return
              end

              -- remove the harpoon item and refresh the list
              list:remove_at(entry.idx)
              refresh_picker()
            end)

            return true
          end,
        })
        :find()
    end

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
          --toggle_telescope_harpoon(harpoon:list())
          toggle_telescope(harpoon:list())
        end,
        desc = "harpoon menu",
      },
    }

    return keys
  end,
}
