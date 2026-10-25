-- Log level-visibility RPCs (host side) and kick / return-to-menu reasons (client side)
local M = {}
local function str(p) local ok, v = pcall(function() local x = p:get(); if type(x) == "userdata" and x.ToString then return x:ToString() end; return tostring(x) end); return ok and v or "?" end
function M.install(log)
  local hooks = {
    { "/Script/Engine.PlayerController:ServerUpdateLevelVisibility", function(self, pkg, vis) log("RPC ServerUpdateLevelVisibility pkg=" .. str(pkg) .. " visible=" .. str(vis)) end },
    { "/Script/Engine.PlayerController:ClientWasKicked", function(self, reason) log("RPC ClientWasKicked reason=" .. str(reason)) end },
    { "/Script/Engine.PlayerController:ClientReturnToMainMenu", function(self, reason) log("RPC ClientReturnToMainMenu reason=" .. str(reason)) end },
    { "/Script/Engine.PlayerController:ClientReturnToMainMenuWithTextReason", function(self, reason) log("RPC ClientReturnToMainMenuWithTextReason reason=" .. str(reason)) end },
    { "/Script/Engine.PlayerController:ClientUpdateLevelStreamingStatus", function(self, pkg, load, vis) log("RPC ClientUpdateLevelStreamingStatus pkg=" .. str(pkg) .. " load=" .. str(load) .. " vis=" .. str(vis)) end },
    { "/Script/Engine.GameplayStatics:SetEnableWorldRendering", function(self, ctx, enable) log("CALL SetEnableWorldRendering enable=" .. str(enable) .. " ctx=" .. str(ctx)) end },
    { "/Script/Engine.GameModeBase:K2_PostLogin", function(self, pc) log("GameMode PostLogin " .. str(pc)) end },
    { "/Script/Engine.GameModeBase:K2_OnLogout", function(self, ctrl) log("GameMode Logout " .. str(ctrl)) end },
  }
  for _, h in ipairs(hooks) do
    local ok, err = pcall(function() RegisterHook(h[1], h[2]) end)
    log("hook " .. h[1] .. " -> " .. (ok and "ok" or ("failed: " .. tostring(err))))
  end
end
return M

-- v13: safe watchers (no native UFunction hooks). Armed by F9/F8 so the startup load is not logged.
M.armed = false
local function cls(o) local ok, v = pcall(function() return o:GetClass():GetFName():ToString() end); return ok and v or "?" end
local function nm(o) local ok, v = pcall(function() return o:GetFName():ToString() end); return ok and v or "?" end
function M.install_watchers(log)
  local ok1 = pcall(function()
    RegisterBeginPlayPostHook(function(actor)
      if not M.armed then return end
      local a = actor
      if type(actor) == "userdata" and actor.get then local okg, v = pcall(function() return actor:get() end); if okg then a = v end end
      log("BEGINPLAY " .. cls(a) .. " " .. nm(a))
    end)
  end)
  log("watcher BeginPlay -> " .. tostring(ok1))
  local ok2 = pcall(function()
    NotifyOnNewObject("/Script/UMG.UserWidget", function(w)
      if M.armed then log("NEW WIDGET " .. cls(w) .. " " .. nm(w)) end
    end)
  end)
  log("watcher new UserWidget -> " .. tostring(ok2))
  local ok3 = pcall(function()
    RegisterProcessConsoleExecPreHook(function(ctx, cmd)
      if M.armed then local okc, c = pcall(function() return cmd:get():ToString() end); log("CONSOLE " .. (okc and c or tostring(cmd))) end
    end)
  end)
  log("watcher console exec -> " .. tostring(ok3))
end
