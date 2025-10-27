-- =========================
-- Druid DoT swapper (1.12)
-- =========================
function TheoDruidSwapDots()
  local u = "target"
  if not UnitExists(u) or UnitIsDeadOrGhost(u) or not UnitCanAttack("player", u) then return end

  local hasMF, hasIS = false, false
  for i=1,16 do
    if not UnitDebuff(u, i) then break end
    GameTooltip:SetOwner(UIParent, "ANCHOR_NONE"); GameTooltip:ClearLines()
    GameTooltip:SetUnitDebuff(u, i)
    local t = (GameTooltipTextLeft1 and GameTooltipTextLeft1:GetText()) or ""
    t = string.lower(t)
    if string.find(t, "moonfire", 1, true) then hasMF = true end
    if string.find(t, "insect swarm", 1, true) then hasIS = true end
    GameTooltip:Hide()
  end

  if hasMF and hasIS then
    CastSpellByName("Wrath")
  elseif hasIS then
    CastSpellByName("Moonfire")
  elseif hasMF then
    CastSpellByName("Insect Swarm")
  else
    CastSpellByName("Moonfire")
  end
end
-- Tiny macro: /run TheoDruidSwapDots()
-- =====================================================
-- Smart QuickHeal router (uses your existing /qh macros)
-- =====================================================

-- Send a slash command safely (1.12)
local function Theo_SendSlash(text)
  local eb = ChatFrameEditBox or (DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.editBox)
  if not eb then return end
  eb:SetText(text)
  ChatEdit_SendText(eb)
end

-- Find lowest % HP friendly unit: raid > party > player
local function Theo_FindLowestUnit()
  local bestUnit, bestPct = nil, 2
  local function consider(unit)
    if UnitExists(unit) and UnitIsFriend("player", unit) and UnitIsConnected(unit) and not UnitIsDeadOrGhost(unit) then
      local hp, maxhp = UnitHealth(unit) or 0, UnitHealthMax(unit) or 1
      local pct = (maxhp > 0) and (hp / maxhp) or 1
      if pct < bestPct then bestPct, bestUnit = pct, unit end
    end
  end

  if GetNumRaidMembers() and GetNumRaidMembers() > 0 then
    for i=1,40 do consider("raid"..i) end
  elseif GetNumPartyMembers() and GetNumPartyMembers() > 0 then
    consider("player")
    for i=1,4 do consider("party"..i) end
  else
    consider("player")
  end
  return bestUnit, bestPct
end

-- Tooltip-based buff check (case-insensitive substring)
local function Theo_UnitHasBuff(unit, needle)
  needle = string.lower(needle)
  for i=1,16 do
    if not UnitBuff(unit, i) then break end
    GameTooltip:SetOwner(UIParent, "ANCHOR_NONE"); GameTooltip:ClearLines()
    GameTooltip:SetUnitBuff(unit, i)
    local t = (GameTooltipTextLeft1 and GameTooltipTextLeft1:GetText()) or ""
    t = string.lower(t)
    GameTooltip:Hide()
    if string.find(t, needle, 1, true) then return true end
  end
  return false
end

-- Main entry: choose /qh or /qh hot based on lowest-HP unit’s HoTs
function TheoSmartQH()
  local unit = Theo_FindLowestUnit()
  if not unit then return end

  local hasRejuv    = Theo_UnitHasBuff(unit, "rejuvenation")
  local hasRegrowth = Theo_UnitHasBuff(unit, "regrowth")

  local cmd
  if hasRejuv and not hasRegrowth then
    cmd = "/qh"
  elseif hasRegrowth and not hasRejuv then
    cmd = "/qh hot"
  else
    -- neither or both → plain /qh
    cmd = "/qh"
  end

  Theo_SendSlash(cmd)
end
