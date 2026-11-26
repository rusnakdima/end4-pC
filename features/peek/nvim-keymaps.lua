-- end4-pC Peek — nvim keymaps (LazyVim).
-- Install: append to ~/.config/nvim/lua/config/keymaps.lua
-- Provided by the theme repo (features/peek/nvim-keymaps.lua).

local function peek_ipc(method, value)
  vim.fn.system({ "qs", "ipc", "-p", "/home/dmitriy/.config/quickshell/end4-pC", "call", "peek", method, value })
end

-- Send the current file to the QuickShell Peek widget.
vim.keymap.set("n", "<leader>p", function()
  local path = vim.fn.expand("%:p")
  if path == "" or vim.fn.filereadable(path) == 0 then
    vim.notify("Peek: current buffer has no readable file", vim.log.levels.WARN)
    return
  end
  peek_ipc("openPath", path)
end, { desc = "Peek: Preview current file" })

-- Send the visual selection as text; Peek writes it to a scratch file.
vim.keymap.set("v", "<leader>p", function()
  local region = vim.fn.getregion(vim.fn.getpos("v"), vim.fn.getpos("."), { type = vim.fn.mode() })
  local text = table.concat(region, "\n")
  if text == "" then return end
  peek_ipc("openText", text)
end, { desc = "Peek: Preview selected text" })

vim.api.nvim_create_user_command("Peek", function(opts)
  local path = opts.args ~= "" and vim.fn.expand(opts.args) or vim.fn.expand("%:p")
  if vim.fn.filereadable(path) == 0 then
    vim.notify("Not a readable file: " .. path, vim.log.levels.ERROR)
    return
  end
  peek_ipc("openPath", path)
end, { nargs = "?", complete = "file", desc = "Preview a file in the shell widget" })
