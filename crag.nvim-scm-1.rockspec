package = "crag.nvim"
version = "scm-1"
source = {
  url = "git+https://github.com/WhitehatD/crag.nvim",
}
description = {
  summary = "Neovim integration for crag governance workflows",
  homepage = "https://github.com/WhitehatD/crag.nvim",
  license = "MIT",
}
dependencies = {
  "lua >= 5.1",
}
build = {
  type = "builtin",
  modules = {
    ["crag"] = "lua/crag/init.lua",
    ["crag.health"] = "lua/crag/health.lua",
  },
}
