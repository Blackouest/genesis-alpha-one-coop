-- v20: log which input-action Blueprint events fire, to find what the guest's actions call.
-- Script hooks on Blueprint functions named InpActEvt_* of the player character, controller and builder.
local M = {}
local function safe(f, d) local ok, v = pcall(f); if ok then return v end; return d end
local CLASSES = {
  "/Game/Blueprints/Player/Eden_PlayerCharacter.Eden_PlayerCharacter_C",
}
M.installed = false

-- Actions the engine already replicates (movement, look, crouch/jump through CharacterMovement) or that are UI noise
local SKIP = { "ChangeInputType", "KeyboardAnyKeyConfirm", "PC_Move", "PC_Look", "PC_Turn", "PC_Jump", "PC_Crouch", "Sprint", "Gamepad" }
M.forwarded = 0

local function skip(name)
  for _, k in ipairs(SKIP) do if name:find(k, 1, true) then return true end end
  return false
end

function M.on_action(log, short, name, selfp)
  if skip(name) then return end
  local me = safe(function() return selfp:get() end)
  local mine = me and safe(function() return me:IsLocallyControlled() end, false)
  log("ACTION " .. short .. "." .. name .. (mine and "" or " (not local)"))
  -- guest: forward its own pawn's actions to the host
  if _G.COOP_ROLE == "client" and mine and short == "Eden_PlayerCharacter_C" then
    local ch = package.loaded["channel"]
    if ch then ch.to_host(log, "act|" .. name); M.forwarded = M.forwarded + 1 end
  end
end

-- host: run a forwarded action on the sender's pawn
function M.run_for_guest(log, sender_pc, name)
  local pawn = safe(function() return sender_pc.Pawn end)
  if not (pawn and safe(function() return pawn:IsValid() end, false)) then log("act: guest has no pawn"); return end
  local fn = safe(function() return pawn[name] end)
  if not fn then log("act: no function " .. name .. " on " .. pawn:GetFName():ToString()); return end
  local imp = package.loaded["impersonate"]
  local ok, err, hits
  if imp and imp.installed then
    local who = { pc = sender_pc, pawn = pawn, cam = safe(function() return sender_pc.PlayerCameraManager end) }
    ok, err, hits = imp.run(log, who, function() fn(pawn, { KeyName = FName("None") }) end)
  else
    ok, err = pcall(function() fn(pawn, { KeyName = FName("None") }) end)
  end
  log("act: ran " .. name .. " on guest pawn " .. pawn:GetFName():ToString() .. " -> " .. (ok and "ok" or tostring(err))
    .. (hits and (" | player0 redirected: " .. (hits ~= "" and hits or "none")) or ""))
end

function M.install(log)
  if M.installed then return end
  local n, total = 0, 0
  for _, short in ipairs({ "Eden_PlayerCharacter_C", "BP_PlayerController_EdenAlpha_C", "BuilderCharacter_C" }) do
    local obj = FindFirstOf(short)
    local cls = obj and safe(function() return obj:GetClass() end)
    if cls then
      local path = safe(function() return cls:GetFullName():match("^%S+%s+(.+)$") end)
      safe(function()
        cls:ForEachFunction(function(fn)
          local name = fn:GetFName():ToString()
          total = total + 1
          if name:find("^InpActEvt_") and path then
            local full = path .. ":" .. name
            local ok = pcall(function()
              RegisterHook(full, function(self) M.on_action(log, short, name, self) end)
            end)
            if ok then n = n + 1 end
          end
        end)
      end)
      log("actions: " .. short .. " (" .. tostring(path) .. ")")
    else
      log("actions: no " .. short .. " yet")
    end
  end
  log("actions: hooked " .. n .. " input action events (of " .. total .. " functions)")
  M.installed = n > 0
end
return M
