-- v25 (host): "impersonation window". While the host runs one of the guest's actions, the engine's
-- "player 0" helpers answer with the guest instead of the host. Needs UE4SS experimental (hook return override).
local M = {}
M.active = nil      -- { pc = ..., pawn = ..., cam = ... } while a guest action runs
M.installed = false
M.hits = {}

local function idx0(p) local ok, v = pcall(function() return p:get() end); return (not ok) or v == 0 end

local TARGETS = {
  { "/Script/Engine.GameplayStatics:GetPlayerController", "pc" },
  { "/Script/Engine.GameplayStatics:GetPlayerCharacter", "pawn" },
  { "/Script/Engine.GameplayStatics:GetPlayerPawn", "pawn" },
  { "/Script/Engine.GameplayStatics:GetPlayerCameraManager", "cam" },
}

function M.install(log)
  if M.installed then return end
  local f = io.open(COOP_BASE .. "noimpersonate.txt", "r")
  if f then f:close(); log("impersonate: disabled by noimpersonate.txt"); return end
  for _, t in ipairs(TARGETS) do
    local path, key = t[1], t[2]
    local ok, err = pcall(function()
      RegisterHook(path, function() end, function(ctx, wco, index)
        local a = M.active
        if a and a[key] and idx0(index) then
          M.hits[key] = (M.hits[key] or 0) + 1
          return a[key]
        end
      end)
    end)
    log("impersonate hook " .. path .. " -> " .. (ok and "ok" or tostring(err)))
  end
  M.installed = true
end

function M.run(log, who, fn)
  M.active = who
  M.hits = {}
  local ok, err = pcall(fn)
  M.active = nil
  local h = {}
  for k, v in pairs(M.hits) do table.insert(h, k .. "=" .. v) end
  return ok, err, table.concat(h, " ")
end
return M
