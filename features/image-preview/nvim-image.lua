-- end4-pC Image Preview — snacks.nvim plugin spec (LazyVim).
-- Install: copy to ~/.config/nvim/lua/plugins/image.lua
-- Provided by the theme repo (features/image-preview/nvim-image.lua).

return {
  "folke/snacks.nvim",
  opts = {
    image = {
      enabled = true,
      -- snacks uses the kitty graphics protocol when available and falls back
      -- to an external converter (magick) otherwise. No `renderer` key exists.
    },
  },
}
