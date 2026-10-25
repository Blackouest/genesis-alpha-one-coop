-- Log level-visibility RPCs (host side) and kick / return-to-menu reasons (client side)
local M = {}
local function who(p) local ok, v = pcall(function() local o = p:get(); return o:GetFName():ToString() end); return ok and v or "?" end
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
    { "/Script/Engine.KismetSystemLibrary:ExecuteConsoleCommand", function(self, ctx, cmd) log("CALL ExecuteConsoleCommand '" .. str(cmd) .. "'") end },
    { "/Script/Engine.PlayerController:ConsoleCommand", function(self, cmd) log("CALL PC.ConsoleCommand '" .. str(cmd) .. "' on " .. who(self)) end },
    { "/Script/Engine.PlayerCameraManager:StartCameraFade", function(self, from, to, dur) log("CALL StartCameraFade " .. str(from) .. "->" .. str(to) .. " dur=" .. str(dur) .. " on " .. who(self)) end },
    { "/Script/Engine.PlayerController:ClientSetCameraFade", function(self, enable) log("RPC ClientSetCameraFade enable=" .. str(enable) .. " on " .. who(self)) end },
    { "/Script/Engine.PlayerController:SetCinematicMode", function(self, on) log("CALL SetCinematicMode " .. str(on) .. " on " .. who(self)) end },
    { "/Script/Engine.PlayerController:ClientSetCinematicMode", function(self, on) log("RPC ClientSetCinematicMode " .. str(on) .. " on " .. who(self)) end },
    { "/Script/Engine.PlayerController:SetViewTargetWithBlend", function(self, t) log("CALL SetViewTargetWithBlend " .. str(t) .. " on " .. who(self)) end },
    { "/Script/Engine.PlayerController:ClientSetViewTarget", function(self, t) log("RPC ClientSetViewTarget " .. str(t) .. " on " .. who(self)) end },
    { "/Script/Engine.GameplayStatics:SetGamePaused", function(self, ctx, p) log("CALL SetGamePaused " .. str(p)) end },
    { "/Script/Engine.GameUserSettings:ApplySettings", function(self) log("CALL GameUserSettings.ApplySettings") end },
    { "/Script/Engine.GameUserSettings:SetScreenResolution", function(self, r) log("CALL SetScreenResolution") end },
    { "/Script/UMG.UserWidget:AddToViewport", function(self, z) log("CALL AddToViewport " .. who(self) .. " z=" .. str(z)) end },
    { "/Script/Engine.GameModeBase:K2_OnLogout", function(self, ctrl) log("GameMode Logout " .. str(ctrl)) end },
  }
  for _, h in ipairs(hooks) do
    local ok, err = pcall(function() RegisterHook(h[1], h[2]) end)
    log("hook " .. h[1] .. " -> " .. (ok and "ok" or ("failed: " .. tostring(err))))
  end
end
return M
