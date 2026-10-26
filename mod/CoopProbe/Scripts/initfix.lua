-- v19: the guest's Eden_PlayerCharacter_C is never initialized by the game.
-- F2 (1st press): list init-like functions on the player classes, show every player character's init state.
-- F2 (2nd press): on every NOT-initialized player character in this world (host: the guest's copy; guest: its own pawn),
--                 copy the host's values: IsPlayerInitialized, BlockActionFPSPlayerInput, speeds, movement component.
local M = {}
local function safe(f, d) local ok, v = pcall(f); if ok then return v end; return d end
local function nm(o) return safe(function() return o:GetFName():ToString() end, "?") end
M.pressed = 0
local WORDS = { "init", "setup", "spawn", "load", "begin", "start", "possess", "ready", "enable", "unblock", "block" }

local function list_functions(log, obj, label)
  local c = safe(function() return obj:GetClass() end)
  local names = {}
  for _ = 1, 3 do
    if not c or not safe(function() return c:IsValid() end, false) then break end
    local cn = nm(c)
    if not cn:find("_C$") then break end  -- only Blueprint classes
    safe(function()
      c:ForEachFunction(function(fn)
        local n = fn:GetFName():ToString()
        local l = n:lower()
        for _, w in ipairs(WORDS) do if l:find(w, 1, true) then table.insert(names, cn .. ":" .. n); break end end
      end)
    end)
    c = safe(function() return c:GetSuperStruct() end)
  end
  log(label .. " functions: " .. table.concat(names, ", "))
end

local GEAR = { "weapon", "inventory", "equip", "builder", "tool", "multitool", "slot", "item", "flashlight", "hud", "widget", "oxygen" }
local function gear(log, ch)
  local out = {}
  local c = safe(function() return ch:GetClass() end)
  for _ = 1, 3 do
    if not c or not safe(function() return c:IsValid() end, false) then break end
    if not nm(c):find("_C$") then break end
    safe(function()
      c:ForEachProperty(function(prop)
        local pn = prop:GetFName():ToString()
        local l = pn:lower()
        local hit = false
        for _, w in ipairs(GEAR) do if l:find(w, 1, true) then hit = true; break end end
        if hit then
          local v = safe(function() return ch[pn] end)
          local t = type(v)
          local shown
          if t == "boolean" or t == "number" then shown = tostring(v)
          elseif t == "userdata" then
            local n = safe(function() return v:GetArrayNum() end)
            if n then shown = "[" .. n .. "]"
            else
              local valid = safe(function() return v:IsValid() end, nil)
              if valid == true then shown = nm(v) elseif valid == false then shown = "none" end
            end
          end
          if shown then table.insert(out, pn .. "=" .. shown) end
        end
      end)
    end)
    c = safe(function() return c:GetSuperStruct() end)
  end
  log("  gear " .. nm(ch) .. ": " .. table.concat(out, " "))
end

local function state(ch)
  return string.format("init=%s block=%s speed=%s mode=%s cmActive=%s maxWalk=%s role=%s",
    tostring(safe(function() return ch.IsPlayerInitialized end, "?")),
    tostring(safe(function() return ch.BlockActionFPSPlayerInput end, "?")),
    tostring(safe(function() return ch.PlayerMovementSpeed end, "?")),
    tostring(safe(function() return ch.CharacterMovement.MovementMode end, "?")),
    tostring(safe(function() return ch.CharacterMovement:IsActive() end, "?")),
    tostring(safe(function() return ch.CharacterMovement.MaxWalkSpeed end, "?")),
    tostring(safe(function() return ch.Role end, "?")))
end

function M.press(log)
  M.pressed = M.pressed + 1
  local chars = {}
  for _, ch in ipairs(FindAllOf("Eden_PlayerCharacter_C") or {}) do if ch:IsValid() then table.insert(chars, ch) end end
  if M.pressed % 2 == 1 then
    log("---- init dump ----")
    if chars[1] then list_functions(log, chars[1], "Eden_PlayerCharacter_C") end
    local pc = FindFirstOf("BP_PlayerController_EdenAlpha_C")
    if pc then list_functions(log, pc, "BP_PlayerController_EdenAlpha_C") end
    for _, ch in ipairs(chars) do log("CHAR " .. nm(ch) .. " " .. state(ch)); gear(log, ch) end
    log("---- end (F2 again on the host = give the guest its weapons with InitWeaponsFromSave) ----")
    return
  end
  if _G.COOP_ROLE == "host" then
    local w = package.loaded["weapons"]
    if w then w.give(log) end
    return
  end
  -- reference values from an initialized character if this world has one
  local speed, maxwalk = 1400.0, 1400.0
  for _, ch in ipairs(chars) do
    if safe(function() return ch.IsPlayerInitialized end, false) == true then
      speed = safe(function() return ch.PlayerMovementSpeed end, speed)
      maxwalk = safe(function() return ch.CharacterMovement.MaxWalkSpeed end, maxwalk)
    end
  end
  for _, ch in ipairs(chars) do
    local role = safe(function() return ch.Role end, 0)
    -- skip simulated proxies (another player's character as seen by a client)
    if role ~= 1 and safe(function() return ch.IsPlayerInitialized end, true) == false then
      local cm = safe(function() return ch.CharacterMovement end)
      safe(function() ch.BlockActionFPSPlayerInput = false end)
      safe(function() ch.PlayerMovementSpeed = speed end)
      safe(function() ch.IsPlayerInitialized = true end)
      if cm then
        safe(function() cm:Activate(true) end)
        safe(function() cm.MaxWalkSpeed = maxwalk end)
        safe(function() cm:SetMovementMode(1, 0) end)
      end
      log("INIT " .. nm(ch) .. " -> " .. state(ch))
    end
  end
  log("---- init done: try to move, switch weapon, open the map ----")
end

-- Automatic version: host initializes the guest's copy (not locally controlled), guest its own pawn.
function M.apply(log, mode)
  local chars = {}
  for _, ch in ipairs(FindAllOf("Eden_PlayerCharacter_C") or {}) do if ch:IsValid() then table.insert(chars, ch) end end
  local speed, maxwalk = 1400.0, 1400.0
  for _, ch in ipairs(chars) do
    if safe(function() return ch.IsPlayerInitialized end, false) == true then
      speed = safe(function() return ch.PlayerMovementSpeed end, speed)
      maxwalk = safe(function() return ch.CharacterMovement.MaxWalkSpeed end, maxwalk)
    end
  end
  for _, ch in ipairs(chars) do
    local mine = safe(function() return ch:IsLocallyControlled() end, false)
    local role = safe(function() return ch.Role end, 0)
    local want = (mode == "host" and role == 3 and not mine) or (mode == "client" and mine)
    if want and safe(function() return ch.IsPlayerInitialized end, true) == false then
      local cm = safe(function() return ch.CharacterMovement end)
      safe(function() ch.BlockActionFPSPlayerInput = false end)
      safe(function() ch.PlayerMovementSpeed = speed end)
      safe(function() ch.IsPlayerInitialized = true end)
      if cm then
        safe(function() cm:Activate(true) end)
        safe(function() cm.MaxWalkSpeed = maxwalk end)
        safe(function() cm:SetMovementMode(1, 0) end)
      end
      log("auto-init (" .. mode .. ") " .. nm(ch) .. " -> " .. state(ch))
    end
  end
end
return M
