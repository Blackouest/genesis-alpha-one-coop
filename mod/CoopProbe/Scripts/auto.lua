-- v17: automatic co-op join flow (prototype)
--  host  : 6 s after F9, export the ship levels (same-PC file hand-off)
--  guest : once connected, import the ship levels, then remove the loading screen
--  both  : if the HUD's FadeOutBorder stays fully black for 6 s, hide it (single-player fade left on by the join)
local M = {}
local function safe(f, d) local ok, v = pcall(f); if ok then return v end; return d end

local function local_pc()
  for _, x in ipairs(FindAllOf("PlayerController") or {}) do
    if x:IsValid() and safe(function() return x:IsLocalController() end, false) then return x end
  end
end

local function connected_client()
  local pc = local_pc(); if not pc then return false end
  local nd = safe(function() return pc:GetWorld().NetDriver end)
  if not (nd and safe(function() return nd:IsValid() end, false)) then return false end
  local sc = safe(function() return nd.ServerConnection end)
  return sc and safe(function() return sc:IsValid() end, false) and safe(function() return pc.Pawn:IsValid() end, false)
end

local black_ticks = 0
-- Several PlayerHudWidget copies can exist (old ones from earlier map loads), so look at all of them:
-- if ANY FadeOutBorder stays fully black for 3 checks in a row, hide every black one.
local function fade_watch(log)
  local black = {}
  for _, b in ipairs(FindAllOf("Border") or {}) do
    if b:IsValid() and safe(function() return b:GetFName():ToString() end, "") == "FadeOutBorder" then
      local vis = safe(function() return b:GetVisibility() end, 1)
      local a = safe(function() return b.BrushColor.A end, 0)
      local op = safe(function() return b:GetRenderOpacity() end, 0)
      if (vis == 0 or vis == 3 or vis == 4) and type(a) == "number" and a > 0.99 and type(op) == "number" and op > 0.99 then
        table.insert(black, b)
      end
    end
  end
  local total = 0
  for _, b in ipairs(FindAllOf("Border") or {}) do
    if b:IsValid() and safe(function() return b:GetFName():ToString() end, "") == "FadeOutBorder" then total = total + 1 end
  end
  local sig = total .. "/" .. #black
  if sig ~= M.last_sig then log("auto: FadeOutBorder copies=" .. total .. " fully black=" .. #black); M.last_sig = sig end
  if #black == 0 then black_ticks = 0; return end
  black_ticks = black_ticks + 1
  if black_ticks >= 3 then
    for _, b in ipairs(black) do safe(function() b:SetVisibility(2) end) end
    log("auto: " .. #black .. " FadeOutBorder fully black for 6 s -> hidden")
    black_ticks = 0
  end
end

function M.start_host(log, levels)
  local t = 0
  LoopAsync(2000, function()
    t = t + 2
    ExecuteInGameThread(function()
      if t == 6 then levels.export(log) end
      fade_watch(log)
      local init = package.loaded["initfix"]
      if init and t > 6 then init.apply(log, "host") end
      local acts = package.loaded["actions"]
      if acts and t > 6 and not acts.installed then acts.install(log) end
      local imp = package.loaded["impersonate"]
      if imp and t > 6 and not imp.installed then imp.install(log) end
      -- once a guest pawn exists and has been initialized, give it weapons and detach it from the host HUD
      local w = package.loaded["weapons"]
      if w and not M.gave and t > 8 then
        for _, ch in ipairs(FindAllOf("Eden_PlayerCharacter_C") or {}) do
          if ch:IsValid() and not safe(function() return ch:IsLocallyControlled() end, true)
             and safe(function() return ch.Role end, 0) == 3 and safe(function() return ch.IsPlayerInitialized end, false) then
            M.gave = true
            log("auto: guest pawn ready, giving weapons")
            w.give(log)
            break
          end
        end
      end
    end)
    return false
  end)
  log("auto: host flow started (export levels at +6 s, fade watch every 2 s)")
end

function M.start_client(log, levels, reveal)
  local phase, wait = "connect", 0
  LoopAsync(2000, function()
    ExecuteInGameThread(function()
      if phase == "connect" then
        if connected_client() then phase = "settle"; wait = 0; log("auto: connected, possessing a pawn") end
      elseif phase == "settle" then
        wait = wait + 2
        if wait >= 4 then levels.import(log); phase = "reveal"; wait = 0 end
      elseif phase == "reveal" then
        wait = wait + 2
        if wait >= 6 then
          reveal.run(log)
          local init = package.loaded["initfix"]
          if init then init.apply(log, "client") end
          local acts = package.loaded["actions"]
          if acts and not acts.installed then acts.install(log) end
          phase = "done"; log("auto: guest flow done")
        end
      end
      fade_watch(log)
    end)
    return false
  end)
  log("auto: guest flow started")
end
return M
