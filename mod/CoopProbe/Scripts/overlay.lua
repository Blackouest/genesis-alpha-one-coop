-- Find full-screen black UMG elements inside the HUD.
-- F1: list Image/Border widgets owned by a visible user widget, with visibility, colour and opacity.
-- Ctrl+F1 is not used; F11 is avoided (UE fullscreen). F1 lists, F1 again (second press) hides the suspects.
local M = {}
local function safe(f, d) local ok, v = pcall(f); if ok then return v end; return d end
local function nm(o) return safe(function() return o:GetFName():ToString() end, "?") end
local function cls(o) return safe(function() return o:GetClass():GetFName():ToString() end, "?") end
local function f3(v) return type(v) == "number" and string.format("%.2f", v) or tostring(v) end
M.suspects = {}
M.listed = false

local function owner_widget(w)
  -- widget -> WidgetTree -> UserWidget
  local tree = safe(function() return w:GetOuter() end)
  local uw = tree and safe(function() return tree:GetOuter() end)
  return uw
end

local function color_of(w, c)
  if c == "Image" then
    local col = safe(function() return w.ColorAndOpacity end)
    if col then return safe(function() return col.R end), safe(function() return col.G end), safe(function() return col.B end), safe(function() return col.A end) end
  elseif c == "Border" then
    local col = safe(function() return w.BrushColor end)
    if col then return safe(function() return col.R end), safe(function() return col.G end), safe(function() return col.B end), safe(function() return col.A end) end
  end
end

function M.press(log)
  if M.listed then return M.hide(log) end
  M.suspects = {}
  local n = 0
  for _, c in ipairs({ "Image", "Border" }) do
    for _, w in ipairs(FindAllOf(c) or {}) do
      if w:IsValid() then
        local uw = owner_widget(w)
        local uwc
        -- nested user widgets are not "in viewport" themselves: climb the outer chain to the top widget
        local inview, top = false, uw
        local o = w
        for _ = 1, 12 do
          o = safe(function() return o:GetOuter() end)
          if not o or not safe(function() return o:IsValid() end, false) then break end
          if safe(function() return o:IsInViewport() end, false) then inview = true; top = o; break end
        end
        uwc = cls(uw) .. (top ~= uw and ("<" .. cls(top)) or "")
        local vis = safe(function() return w:GetVisibility() end, "?")
        local op = safe(function() return w:GetRenderOpacity() end, "?")
        local r, g, b, a = color_of(w, c)
        local visible = (vis == 0 or vis == 3 or vis == 4)
        if inview and visible then
          n = n + 1
          local dark = type(r) == "number" and r < 0.1 and g < 0.1 and b < 0.1 and (a or 0) > 0.5
          log(string.format("%s %s in %s vis=%s opacity=%s color=%s,%s,%s,%s%s", c, nm(w), uwc, tostring(vis), f3(op), f3(r), f3(g), f3(b), f3(a), dark and "  <-- DARK" or ""))
          if dark and nm(w) == "FadeOutBorder" then table.insert(M.suspects, w) end
        end
      end
    end
  end
  log("overlay: " .. n .. " visible images/borders in viewport widgets, " .. #M.suspects .. " dark suspects. Press F1 again to hide the suspects.")
  M.listed = true
end

function M.hide(log)
  for _, w in ipairs(M.suspects) do
    if w:IsValid() then
      safe(function() w:SetVisibility(2) end)  -- Hidden
      log("overlay: hid " .. cls(w) .. " " .. nm(w) .. " in " .. cls(owner_widget(w)))
    end
  end
  M.listed = false
end
return M
