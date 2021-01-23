local helpers = require "spec.helpers"
local myhelpers = require "spec.myhelpers"
local strategies = require("kong.plugins.proxy-cache.strategies")

local strategy_wait_appear = myhelpers.wait_appear

-- Set up 2 kong  servrootA & servrootB using cassandra ans postgres
-- With 2 hosts serving route1.com sharing the cache between the both kong
-- route2.com each kong having a dedicated redis database

do
  local configs = {
    redis0 = {
      host = helpers.redis_host,
      port = 6379,
      database = 0,
    },
    redis1 = {
      host = helpers.redis_host,
      port = 6379,
      database = 1,
    },
    redis2 = {
      host = helpers.redis_host,
      port = 6379,
      database = 2,
    },
  }
  local policy = "redis"
  describe("proxy-cache redis", function()
    local clientA
    local clientB

    local strategy0 = strategies({
      strategy_name = policy,
      strategy_opts = configs.redis0,
    })
    local strategy1 = strategies({
      strategy_name = policy,
      strategy_opts = configs.redis1,
    })
    local strategy2 = strategies({
      strategy_name = policy,
      strategy_opts = configs.redis2,
    })

    setup(function()

      local bp1 = helpers.get_db_utils("cassandra", nil, {"proxy-cache"})

      local routeA1 = assert(bp1.routes:insert {
        hosts = { "route-1.com" },
      })
      local routeA2 = assert(bp1.routes:insert {
        hosts = { "route-2.com" },
      })
      assert(bp1.plugins:insert {
        name = "proxy-cache",
        route = { id = routeA1.id },
        config = {
          strategy = policy,
          content_type = { "text/plain", "application/json" },
          redis = configs.redis0,
        },
      })

      assert(bp1.plugins:insert {
        name = "proxy-cache",
        route = { id = routeA2.id },
        config = {
          strategy = policy,
          content_type = { "text/plain", "application/json" },
          redis = configs.redis1,
        },
      })

      local bp2 = helpers.get_db_utils("postgres", nil, {"proxy-cache"})
      local routeB1 = assert(bp2.routes:insert {
        hosts = { "route-1.com" },
        id = routeA1.id, -- force id to share same cache key
      })
      local routeB2 = assert(bp2.routes:insert {
        hosts = { "route-2.com" },
        id = routeA2.id,
      })


      assert(bp2.plugins:insert {
        name = "proxy-cache",
        route = { id = routeB1.id },
        config = {
          strategy = policy,
          content_type = { "text/plain", "application/json" },
          redis = configs.redis0,
        },
      })

      assert(bp2.plugins:insert {
        name = "proxy-cache",
        route = { id = routeB2.id },
        config = {
          strategy = policy,
          content_type = { "text/plain", "application/json" },
          redis = configs.redis2,
        },
      })
      assert(helpers.start_kong {
        log_level             = "debug",
        prefix                = "servrootA",
        database              = "cassandra",
        proxy_listen          = "0.0.0.0:8000",
        proxy_listen_ssl      = "0.0.0.0:8443",
        admin_listen          = "0.0.0.0:8001",
        admin_gui_listen      = "0.0.0.0:8002",
        admin_ssl             = false,
        admin_gui_ssl         = false,
        plugins               = "proxy-cache",
        nginx_conf            = "spec/fixtures/custom_nginx.template",
      })

      assert(helpers.start_kong {
        log_level             = "debug",
        prefix                = "servrootB",
        database              = "postgres",
        proxy_listen          = "0.0.0.0:9000",
        proxy_listen_ssl      = "0.0.0.0:9443",
        admin_listen          = "0.0.0.0:9001",
        admin_gui_listen      = "0.0.0.0:9002",
        admin_ssl             = false,
        admin_gui_ssl         = false,
        plugins               = "proxy-cache",
      })

    end)


    before_each(function()
      strategy0:flush(true)
      strategy1:flush(true)
      strategy2:flush(true)
      if clientA then
        clientA:close()
      end
      if clientB then
        clientB:close()
      end
      clientA = helpers.http_client("127.0.0.1", 8000)
      clientB = helpers.http_client("127.0.0.1", 9000)
    end)


    teardown(function()
      if clientA then
        clientA:close()
      end
      if clientB then
        clientB:close()
      end

      helpers.stop_kong("servrootA", true)
      helpers.stop_kong("servrootB", true)
    end)

    it("caches and share a simple request", function()
      local res = assert(clientA:send {
        method = "GET",
        path = "/get",
        headers = {
          host = "route-1.com",
        }
      })

      local body1 = assert.res_status(200, res)
      assert.same("Miss", res.headers["X-Cache-Status"])

      local cache_key1 = res.headers["X-Cache-Key"]

      -- wait until the underlying strategy converges
      strategy_wait_appear(policy, strategy0, cache_key1)

      res = assert(clientA:send {
        method = "GET",
        path = "/get",
        headers = {
          host = "route-1.com",
        }
      })

      local body2 = assert.res_status(200, res)
      assert.same("Hit", res.headers["X-Cache-Status"])
      local cache_key2 = res.headers["X-Cache-Key"]
      assert.same(cache_key1, cache_key2)

      -- assert that response bodies are identical
      assert.same(body1, body2)

      res = assert(clientB:send {
        method = "GET",
        path = "/get",
        headers = {
          host = "route-1.com",
        }
      })
      assert.same(cache_key1, res.headers["X-Cache-Key"])
      assert.same("Hit", res.headers["X-Cache-Status"])

    end)
    it("caches and don't share a simple request", function()
      local res = assert(clientA:send {
        method = "GET",
        path = "/get",
        headers = {
          host = "route-2.com",
        }
      })

      assert.same("Miss", res.headers["X-Cache-Status"])

      local cache_key1 = res.headers["X-Cache-Key"]

      -- wait until the underlying strategy converges
      strategy_wait_appear(policy, strategy1, cache_key1)

      clientA:close()
      clientA = helpers.http_client("127.0.0.1", 8000)
      res = assert(clientA:send {
        method = "GET",
        path = "/get",
        headers = {
          host = "route-2.com",
        }
      })
      assert.same("Hit", res.headers["X-Cache-Status"])

      res = assert(clientB:send {
        method = "GET",
        path = "/get",
        headers = {
          host = "route-2.com",
        }
      })
      assert.same(cache_key1, res.headers["X-Cache-Key"])
      assert.same("Miss", res.headers["X-Cache-Status"])

      strategy_wait_appear(policy, strategy2, cache_key1)
      clientB:close()
      clientB = helpers.http_client("127.0.0.1", 9000)
      res = assert(clientB:send {
        method = "GET",
        path = "/get",
        headers = {
          host = "route-2.com",
        }
      })
      assert.same("Hit", res.headers["X-Cache-Status"])

    end)
  end)
end
