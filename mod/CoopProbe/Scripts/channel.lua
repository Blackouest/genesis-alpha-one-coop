-- v20: guest <-> host message channel over existing engine RPCs (no new RPCs needed)
--   guest -> host : PlayerController.ServerChangeName("COOP|<msg>")  (reliable server RPC with a string)
--   host -> guest : PlayerController.ClientMessage("COOP|<msg>")      (reliable client RPC with a string)
-- F6 on the guest sends a ping; the host answers pong.
local M = {}
local function safe(f, d) local ok, v = pcall(f); if ok then return v end; return d end
local function sget(p) return safe(function() local x = p:get(); if type(x) == "userdata" and x.ToString then return x:ToString() end; return tostring(x) end, "?") end
M.handlers = {}

local function local_pc()
  for _, x in ipairs(FindAllOf("PlayerController") or {}) do
    if x:IsValid() and safe(function() return x:IsLocalController() end, false) then return x end
  end
end

function M.to_host(log, msg)
  local pc = local_pc(); if not pc then log("channel: no local PC"); return end
  local ok, err = pcall(function() pc:ServerChangeName("COOP|" .. msg) end)
  log("channel -> host '" .. msg .. "' " .. (ok and "sent" or tostring(err)))
end

function M.to_guest(log, guest_pc, msg)
  local ok, err = pcall(function() guest_pc:ClientMessage("COOP|" .. msg, FName("None"), 0.0) end)
  log("channel -> guest '" .. msg .. "' " .. (ok and "sent" or tostring(err)))
end

function M.install(log)
  local ok1, e1 = pcall(function()
    RegisterHook("/Script/Engine.PlayerController:ServerChangeName", function(self, s)
      local msg = sget(s)
      if msg:sub(1, 5) ~= "COOP|" then return end
      local body = msg:sub(6)
      local sender = safe(function() return self:get() end)
      log("channel <- guest '" .. body .. "' from " .. safe(function() return sender:GetFName():ToString() end, "?"))
      local cmd = body:match("^(%w+)")
      if cmd == "act" then
        local name = body:match("^act|(.+)$")
        local a = package.loaded["actions"]
        if name and a then ExecuteInGameThread(function() a.run_for_guest(log, sender, name) end) end
        return
      end
      if cmd == "ping" then M.to_guest(log, sender, "pong " .. body:sub(6)) end
      local h = M.handlers[cmd]
      if h then pcall(h, log, sender, body) end
    end)
  end)
  log("channel hook ServerChangeName -> " .. (ok1 and "ok" or tostring(e1)))
  local ok2, e2 = pcall(function()
    RegisterHook("/Script/Engine.PlayerController:ClientMessage", function(self, s)
      local msg = sget(s)
      if msg:sub(1, 5) == "COOP|" then log("channel <- host '" .. msg:sub(6) .. "'") end
    end)
  end)
  log("channel hook ClientMessage -> " .. (ok2 and "ok" or tostring(e2)))
end
return M
