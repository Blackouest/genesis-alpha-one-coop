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
local function fade_watch(log)
  for _, b in ipairs(FindAllOf("Border") or {}) do
    if b:IsValid() and safe(function() return b:GetFName():ToString() end, "") == "FadeOutBorder" then
      local vis = safe(function() return b:GetVisibility() end, 1)
      local a = safe(function() return b.BrushColor.A end, 0)
      local op = safe(function() return b:GetRenderOpacity() end, 0)
      if (vis == 0 or vis == 3 or vis == 4) and a > 0.99 and op > 0.99 then
        black_ticks = black_ticks + 1
        if black_ticks >= 3 then
          safe(function() b:SetVisibility(2) end)
          log("auto: FadeOutBorder was fully black for 6 s -> hidden")
          black_ticks = 0
        end
      else
        black_ticks = 0
      end
    end
  end
end

function M.start_host(log, levels)
  local t = 0
  LoopAsync(2000, function()
    t = t + 2
    ExecuteInGameThread(function()
      if t == 6 then levels.export(log) end
      fade_watch(log)
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
        if wait >= 6 then reveal.run(log); phase = "done"; log("auto: guest flow done") end
      end
      fade_watch(log)
    end)
    return false
  end)
  log("auto: guest flow started")
end
return M
