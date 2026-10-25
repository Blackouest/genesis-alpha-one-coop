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
