-- =============================================================================
-- Core Node — API Key Authentication & Rate Limiting
-- =============================================================================
-- Runs in the OpenResty access_by_lua_file phase.
--
-- API keys are loaded from /etc/openresty/api_keys into a shared dict on
-- first request. Each key gets a token-bucket rate limiter in shared memory.
--
-- Keys file format (one per line):
--   KEY_VALUE:optional-label
--   # comments and blank lines are ignored
--
-- Environment variables (set in docker-compose):
--   API_KEYS_ENABLED  — "true" to require keys (default: "false")
--   RATE_LIMIT_RPS    — requests per second per key (default: 10)
--   RATE_LIMIT_BURST  — burst capacity per key (default: 20)
-- =============================================================================

local API_KEYS_ENABLED = (os.getenv("API_KEYS_ENABLED") or "false") == "true"
local RATE_LIMIT_RPS   = tonumber(os.getenv("RATE_LIMIT_RPS") or "10")
local RATE_LIMIT_BURST = tonumber(os.getenv("RATE_LIMIT_BURST") or "20")

-- If API keys are disabled, allow all requests
if not API_KEYS_ENABLED then
    return
end

-- ---------------------------------------------------------------------------
-- Load keys into shared dict (once, on first request per worker cycle)
-- ---------------------------------------------------------------------------
local keys_dict = ngx.shared.api_keys

if not keys_dict:get("_loaded") then
    local f = io.open("/etc/openresty/api_keys", "r")
    if f then
        for line in f:lines() do
            line = line:match("^%s*(.-)%s*$")  -- trim whitespace
            if line ~= "" and line:sub(1, 1) ~= "#" then
                local key_val = line:match("^([^:]+)")
                if key_val then
                    keys_dict:set("key:" .. key_val, true)
                end
            end
        end
        f:close()
    end
    keys_dict:set("_loaded", true)
end

-- ---------------------------------------------------------------------------
-- Extract API key from header or query parameter
-- ---------------------------------------------------------------------------
local api_key = ngx.req.get_headers()["X-API-Key"]

if not api_key then
    -- Fallback to query param (useful for WebSocket clients)
    local args = ngx.req.get_uri_args()
    api_key = args["api_key"]
end

if not api_key then
    ngx.status = 401
    ngx.header["Content-Type"] = "application/json"
    ngx.say('{"error":"Missing API key. Provide X-API-Key header or ?api_key= parameter."}')
    return ngx.exit(401)
end

-- ---------------------------------------------------------------------------
-- Validate key
-- ---------------------------------------------------------------------------
if not keys_dict:get("key:" .. api_key) then
    ngx.status = 403
    ngx.header["Content-Type"] = "application/json"
    ngx.say('{"error":"Invalid API key."}')
    return ngx.exit(403)
end

-- ---------------------------------------------------------------------------
-- Per-key rate limiting (token bucket)
-- ---------------------------------------------------------------------------
local limit_dict = ngx.shared.rate_limit
local now = ngx.now()
local bucket_key = "rl:" .. api_key

local last_time = limit_dict:get(bucket_key .. ":t")
local tokens    = limit_dict:get(bucket_key .. ":n")

if last_time == nil then
    last_time = now
    tokens = RATE_LIMIT_BURST
end

-- Refill tokens based on elapsed time
local elapsed = now - last_time
tokens = math.min(RATE_LIMIT_BURST, tokens + elapsed * RATE_LIMIT_RPS)

if tokens < 1 then
    ngx.status = 429
    ngx.header["Content-Type"] = "application/json"
    ngx.header["Retry-After"] = tostring(math.ceil((1 - tokens) / RATE_LIMIT_RPS))
    ngx.say('{"error":"Rate limit exceeded. Try again later."}')
    return ngx.exit(429)
end

-- Consume one token
tokens = tokens - 1
limit_dict:set(bucket_key .. ":t", now, 3600)
limit_dict:set(bucket_key .. ":n", tokens, 3600)
