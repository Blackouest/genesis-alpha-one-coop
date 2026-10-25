-- F3 (client): report level visibility, force levels visible, hide the loading screen widget
local M = {}
local function safe(f, d) local ok, v = pcall(f); if ok then return v end; return d end
local function short(o) return safe(function() return (o and o:IsValid()) and o:GetFName():ToString() or "none" end, "err") end

function M.run(log)
  local pc
  for _, x in ipairs(FindAllOf("PlayerController") or {}) do
    if x:IsValid() and safe(function() return x:IsLocalController() end, false) then pc = x end
  end
  if not pc then log("reveal: no local PC"); return end
  local world = pc:GetWorld()
  local vis, total = 0, 0
  world.StreamingLevels:ForEach(function(i, e)
    local sl = e:get()
    total = total + 1
    local loaded = safe(function() return sl:IsLevelLoaded() end, "?")
    local visible = safe(function() return sl:IsLevelVisible() end, "?")
    local should = safe(function() return sl:ShouldBeLoaded() end, "?")
    if visible == true then vis = vis + 1 end
    if i <= 3 or visible ~= true then
      log(string.format("  [%d] loaded=%s visible=%s shouldBeLoaded=%s", i, tostring(loaded), tostring(visible), tostring(should)))
    end
    safe(function() sl:SetShouldBeLoaded(true) end)
    safe(function() sl:SetShouldBeVisible(true) end)
  end)
  log(string.format("reveal: %d/%d levels visible before forcing", vis, total))
  for _, w in ipairs(FindAllOf("LoadingScreen_Widget_C") or {}) do
    if w:IsValid() then
      local before = safe(function() return w:GetVisibility() end, "?")
      safe(function() w:SetVisibility(1) end)  -- 1 = Collapsed
      safe(function() w:RemoveFromParent() end)
      log("reveal: LoadingScreen " .. short(w) .. " visibility " .. tostring(before) .. " -> collapsed/removed")
    end
  end
end
return M
