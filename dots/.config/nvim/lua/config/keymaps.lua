-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- Image preview keymaps are provided by the end4-pC theme (appended below).
-- >>> end4-pC image-preview keymaps >>>
-- end4-pC Image Preview — nvim keymaps (LazyVim).
-- Install: append to ~/.config/nvim/lua/config/keymaps.lua
-- Provided by the theme repo (features/image-preview/nvim-keymaps.lua).

-- Hover an image referenced at the cursor (Markdown, etc.).
vim.keymap.set("n", "<leader>i", function()
  require("snacks").image.hover()
end, { desc = "Image: Hover preview" })

-- Open an image path (prompt when the cursor file is not readable).
vim.keymap.set("n", "<leader>I", function()
  local file = vim.fn.expand("<cfile>")
  if file == "" or vim.fn.filereadable(file) == 0 then
    file = vim.fn.input("Image path: ", vim.fn.expand("%:p:h") .. "/")
  end
  if file == "" or vim.fn.filereadable(file) == 0 then return end
  vim.cmd("edit " .. vim.fn.fnameescape(file))
end, { desc = "Image: Open preview" })

-- Send the current file to the QuickShell Image Preview widget.
vim.keymap.set("n", "<leader><leader>i", function()
  local path = vim.fn.expand("%:p")
  vim.fn.system({ "qs", "ipc", "call", "imagePreview", "openPath", path })
end, { desc = "Image: Send path to shell widget" })

vim.api.nvim_create_user_command("ImagePreview", function(opts)
  local path = opts.args ~= "" and opts.args or vim.fn.expand("%:p")
  if vim.fn.filereadable(path) == 0 then
    vim.notify("Not a readable file: " .. path, vim.log.levels.ERROR)
    return
  end
  vim.cmd("edit " .. vim.fn.fnameescape(path))
end, { nargs = "?", complete = "file", desc = "Preview an image inline" })
-- <<< end4-pC image-preview keymaps <<<
