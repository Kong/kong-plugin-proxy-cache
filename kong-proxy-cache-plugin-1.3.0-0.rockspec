package = "kong-proxy-cache-plugin"
version = "1.3.0-0"

source = {
  url = "git://github.com/Kong/kong-plugin-proxy-cache",
  tag = "1.3.0"
}

supported_platforms = {"linux", "macosx"}

description = {
  summary = "HTTP Proxy Caching for Kong",
  license = "Apache 2.0",
}

dependencies = {
  "lua >= 5.1",
}

build = {
  type = "builtin",
  modules = {
    ["kong.plugins.proxy-cache.handler"]              = "kong/plugins/proxy-cache/handler.lua",
    ["kong.plugins.proxy-cache.cache_key"]            = "kong/plugins/proxy-cache/cache_key.lua",
    ["kong.plugins.proxy-cache.schema"]               = "kong/plugins/proxy-cache/schema.lua",
    ["kong.plugins.proxy-cache.api"]                  = "kong/plugins/proxy-cache/api.lua",
    ["kong.plugins.proxy-cache.strategies"]           = "kong/plugins/proxy-cache/strategies/init.lua",
    ["kong.plugins.proxy-cache.strategies.memory"]    = "kong/plugins/proxy-cache/strategies/memory.lua",
  }
}
