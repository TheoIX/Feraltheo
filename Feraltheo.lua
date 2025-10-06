-- QuickTheoFeral.lua – Feral Druid helper for Turtle WoW (1.12)
-- Clean, copy‑paste ready. No combat-log dependency. Uses swing timer only for Maul.
-- Slash:
--   /theobear   → Bear rotation (auto-shift to Bear/Dire Bear)
--   /theocat    → Cat  rotation (auto-shift to Cat)
--   /swiper     → Bear toggle: force Swipe as primary (suppresses Maul filler)
--   /bleeder    → Cat  toggle: disable bleeds (skip Rake/Rip; favor Bite)

local BOOKTYPE_SPELL = BOOKTYPE_SPELL or "spell"

-- =====================
-- Toggles
-- =====================
QuickTheoFeral_ForceSwipe    = QuickTheoFeral_ForceSwipe    or false -- /swiper
QuickTheoFeral_DisableBleeds = QuickTheoFeral_DisableBleeds or false -- /bleeder

-- Pause Shred after a "not behind/facing" UI error
local NOT_BEHIND_LOCK = 0.8
local NotBehindUntil = 0

-- Short refs
local sfind, slower, smatch = string.find, string.lower, string.match

-- =====================
-- Tooltip scanners
-- =====================
local function UnitHasBuffByName(unit, namePart)
  for i = 1, 40 do
    GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    GameTooltip:SetUnitBuff(unit, i)
    local t = GameTooltipTextLeft1 and GameTooltipTextLeft1:GetText()
    if t and sfind(t, namePart) then return true end
  end
  return false
end

local function UnitHasDebuffByName(unit, namePart)
  for i = 1, 16 do
    GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    GameTooltip:SetUnitDebuff(unit, i)
    local t = GameTooltipTextLeft1 and GameTooltipTextLeft1:GetText()
    if t and sfind(t, namePart) then return true end
  end
  return false
end

-- =====================
-- Cooldown helper
-- =====================
local function IsSpellReady(spellName)
  for idx = 1, 300 do
    local name, rank = GetSpellName(idx, BOOKTYPE_SPELL)
    if not name then break end
    if name == spellName then
      local start, duration = GetSpellCooldown(idx, BOOKTYPE_SPELL)
      if not start or duration == 0 then return true end
      return (start + duration) <= GetTime()
    end
  end
  return false
end

-- =====================
-- Resource gates
-- =====================
local ENERGY_COST = {
  ["Claw"]            = 34,
  ["Tiger's Fury"]   = 30,
  ["Rake"]            = 29,
  ["Shred"]           = 57,
  ["Rip"]             = 30,
  ["Ferocious Bite"]  = 35,
}
local RAGE_COST = {
  ["Savage Bite"]       = 25,
  ["Swipe"]             = 15,
  ["Maul"]              = 10,
  ["Demoralizing Roar"] = 10,
}
local function HasEnergyFor(spell)
  local need = ENERGY_COST[spell]
  if not need then return true end
  if UnitPowerType("player") ~= 3 then return false end
  return (UnitMana("player") or 0) >= need
end
local function HasRageFor(spell)
  local need = RAGE_COST[spell]
  if not need then return true end
  if UnitPowerType("player") ~= 1 then return false end
  return (UnitMana("player") or 0) >= need
end

-- =====================
-- Target / range helpers
-- =====================
local function InMeleeRange(spell)
  if not UnitExists("target") or not UnitCanAttack("player","target") or UnitIsDeadOrGhost("target") then
    return false
  end
  local r = IsSpellInRange and IsSpellInRange(spell, "target")
  if r == 1 then return true end
  if r == 0 then return false end
  -- nil: some melee specials; fallback: 10-yd interact check (3)
  return (CheckInteractDistance and CheckInteractDistance("target", 3) == 1) or false
end

local function InStrictMelee()
  if not UnitExists("target") or not UnitCanAttack("player","target") or UnitIsDeadOrGhost("target") then return false end
  local r1 = IsSpellInRange and IsSpellInRange("Maul","target")
  local r2 = IsSpellInRange and IsSpellInRange("Swipe","target")
  if r1 == 1 or r2 == 1 then return true end
  if r1 == 0 and r2 == 0 then return false end
  return false
end

local function TargetHPpct()
  if not UnitExists("target") then return 100 end
  local hp, maxhp = UnitHealth("target"), UnitHealthMax("target")
  if not maxhp or maxhp == 0 then return 100 end
  return (hp / maxhp) * 100
end

local function IsTargetBleedImmune()
  local ct = UnitCreatureType and UnitCreatureType("target")
  if not ct then return false end
  return (ct == "Elemental" or ct == "Mechanical")
end

-- =====================
-- Pure SwingTimer integration for Maul (no combat log)
-- st_timer: elapsed or remaining; st_timerMax: period. We detect wraps either way.
-- =====================
local SWING_WINDOW = 0.40            -- seconds from a swing (pre or post)
QuickTheoFeral_MaulQueued = QuickTheoFeral_MaulQueued or false

local ST_prevFrac = nil
local stPoll = CreateFrame("Frame")
stPoll:SetScript("OnUpdate", function()
  local st  = type(st_timer) == "number" and st_timer or nil
  local smax= type(st_timerMax) == "number" and st_timerMax or nil
  if st and smax and smax > 0 then
    local frac = st / smax
    if ST_prevFrac then
      if (frac < 0.10 and ST_prevFrac > 0.90) or (frac > 0.90 and ST_prevFrac < 0.10) then
        QuickTheoFeral_MaulQueued = false -- new swing cycle
      end
    end
    ST_prevFrac = frac
  else
    ST_prevFrac = nil
  end
end)

local function InMaulWindow()
  local st  = type(st_timer) == "number" and st_timer or nil
  local smax= type(st_timerMax) == "number" and st_timerMax or nil
  if not (st and smax and smax > 0) then return false end
  local t1 = st
  local t2 = smax - st
  local timeLeft = (t1 < t2) and t1 or t2
  return timeLeft <= SWING_WINDOW
end

-- =====================
-- Form helpers (auto-shift on first press)
-- =====================
local function EnsureBearForm()
  if UnitPowerType("player") == 1 then return true end
  local n = GetNumShapeshiftForms and GetNumShapeshiftForms() or 0
  for i=1,n do
    local _, name, active = GetShapeshiftFormInfo(i)
    if name and (sfind(name, "Dire Bear") or sfind(name, "Bear Form")) then
      if not active then CastShapeshiftForm(i) end
      return true
    end
  end
  return false
end

local function EnsureCatForm()
  if UnitPowerType("player") == 3 then return true end
  local n = GetNumShapeshiftForms and GetNumShapeshiftForms() or 0
  for i=1,n do
    local _, name, active = GetShapeshiftFormInfo(i)
    if name and sfind(name, "Cat Form") then
      if not active then CastShapeshiftForm(i) end
      return true
    end
  end
  return false
end

-- =====================
-- BEAR abilities
-- =====================
local function Cast_SavageBite()
  if not (IsSpellReady("Savage Bite") and HasRageFor("Savage Bite") and InMeleeRange("Savage Bite")) then return false end
  CastSpellByName("Savage Bite"); return true
end
local function Cast_Swipe()
  if not (IsSpellReady("Swipe") and HasRageFor("Swipe") and InMeleeRange("Swipe")) then return false end
  CastSpellByName("Swipe"); return true
end
local function Cast_Maul()
  if QuickTheoFeral_MaulQueued then return false end
  if not InMaulWindow() then return false end
  if not (IsSpellReady("Maul") and HasRageFor("Maul") and InMeleeRange("Maul")) then return false end
  CastSpellByName("Maul")
  QuickTheoFeral_MaulQueued = true
  return true
end
local function Cast_DemoRoar()
  if UnitHasDebuffByName("target","Demoralizing Roar") then return false end
  if not (IsSpellReady("Demoralizing Roar") and HasRageFor("Demoralizing Roar") and InStrictMelee()) then return false end
  CastSpellByName("Demoralizing Roar"); return true
end

-- =====================
-- CAT abilities
-- =====================
local function Cast_TigersFury()
  if UnitHasBuffByName("player","Tiger's Fury") then return false end
  if not (IsSpellReady("Tiger's Fury") and HasEnergyFor("Tiger's Fury")) then return false end
  CastSpellByName("Tiger's Fury"); return true
end
local function Cast_Rake()
  if QuickTheoFeral_DisableBleeds or IsTargetBleedImmune() or UnitHasDebuffByName("target","Rake") then return false end
  if not (IsSpellReady("Rake") and HasEnergyFor("Rake") and InMeleeRange("Rake")) then return false end
  CastSpellByName("Rake"); return true
end
local function Cast_Shred()
  if GetTime() < NotBehindUntil then return false end
  if not (IsSpellReady("Shred") and HasEnergyFor("Shred") and InMeleeRange("Shred")) then return false end
  CastSpellByName("Shred"); return true
end
local function Cast_Rip()
  if QuickTheoFeral_DisableBleeds or IsTargetBleedImmune() or UnitHasDebuffByName("target","Rip") then return false end
  if not (IsSpellReady("Rip") and HasEnergyFor("Rip") and InMeleeRange("Rip")) then return false end
  CastSpellByName("Rip"); return true
end
local function Cast_FerociousBite()
  if not (IsSpellReady("Ferocious Bite") and HasEnergyFor("Ferocious Bite") and InMeleeRange("Ferocious Bite")) then return false end
  CastSpellByName("Ferocious Bite"); return true
end
local function Cast_Claw()
  if not (IsSpellReady("Claw") and HasEnergyFor("Claw") and InMeleeRange("Claw")) then return false end
  CastSpellByName("Claw"); return true
end

-- =====================
-- Rotations
-- =====================
function QuickTheoBear()
  if UnitPowerType("player") ~= 1 then if EnsureBearForm() then return end end
  if not (UnitExists("target") and UnitCanAttack("player","target") and not UnitIsDeadOrGhost("target")) then return end

  -- 1) Savage Bite top prio
  if Cast_SavageBite() then return end
  -- 2) Demo Roar if missing
  if Cast_DemoRoar() then return end

  -- 2.5) Force Swipe mode: Swipe first; if not castable, allow Maul
  if QuickTheoFeral_ForceSwipe then
    if Cast_Swipe() then return end
    if Cast_Maul() then return end
  end

  -- 3) Default single-target: Maul as filler (queued only in swing window)
  if Cast_Maul() then return end
end

function QuickTheoCat()
  if UnitPowerType("player") ~= 3 then if EnsureCatForm() then return end end
  if not (UnitExists("target") and UnitCanAttack("player","target") and not UnitIsDeadOrGhost("target")) then return end

  local cp = (GetComboPoints and GetComboPoints("player","target")) or 0
  local hpct = TargetHPpct()

  -- 0) Tiger's Fury
  if Cast_TigersFury() then return end

  -- 1) 5 CP finisher
  if cp >= 5 then
    if QuickTheoFeral_DisableBleeds or IsTargetBleedImmune() or (hpct <= 50) then
      if Cast_FerociousBite() then return end
    else
      if Cast_Rip() then return end
    end
  end

  -- 2) Rake if missing (and bleeds enabled & not immune)
  if Cast_Rake() then return end
   -- 4) Claw filler
  if Cast_Claw() then return end
    -- 3) Shred prio builder (auto-pauses after not-behind UI error)
  if Cast_Shred() then return end
end

-- =====================
-- Events + Slash
-- =====================
local evt = CreateFrame("Frame")
evt:RegisterEvent("PLAYER_LOGIN")
evt:RegisterEvent("UI_ERROR_MESSAGE")

evt:SetScript("OnEvent", function(_, event, arg1)
  if event == "PLAYER_LOGIN" then
    DEFAULT_CHAT_FRAME:AddMessage("QuickTheoFeral loaded! Use /theobear or /theocat", 0, 1, 0)
  elseif event == "UI_ERROR_MESSAGE" then
    local msg = tostring(arg1 or "")
    local m = slower(msg)
    if sfind(m, "behind") or sfind(m, "facing") then
      NotBehindUntil = GetTime() + NOT_BEHIND_LOCK
    end
  end
end)

-- Slash commands
SLASH_THEOBEAR1 = "/theobear"; SlashCmdList["THEOBEAR"] = QuickTheoBear
SLASH_THEOCAT1  = "/theocat";  SlashCmdList["THEOCAT"]  = QuickTheoCat

SLASH_SWIPER1 = "/swiper"
SlashCmdList["SWIPER"] = function()
  QuickTheoFeral_ForceSwipe = not QuickTheoFeral_ForceSwipe
  if QuickTheoFeral_ForceSwipe then
    DEFAULT_CHAT_FRAME:AddMessage("QuickTheoFeral: Swipe-Force |cff00ff00ENABLED|r (bear)", 0,1,0)
  else
    DEFAULT_CHAT_FRAME:AddMessage("QuickTheoFeral: Swipe-Force |cffff0000DISABLED|r (bear)", 1,0,0)
  end
end

SLASH_BLEEDER1 = "/bleeder"
SlashCmdList["BLEEDER"] = function()
  QuickTheoFeral_DisableBleeds = not QuickTheoFeral_DisableBleeds
  if QuickTheoFeral_DisableBleeds then
    DEFAULT_CHAT_FRAME:AddMessage("QuickTheoFeral: Bleeds |cffff0000DISABLED|r (Cat)", 1,0,0)
  else
    DEFAULT_CHAT_FRAME:AddMessage("QuickTheoFeral: Bleeds |cff00ff00ENABLED|r (Cat)", 0,1,0)
  end

end
