-- ═══════════════════════════════════════════════════════════════════════════════
-- ProjectAstral Brightness System
-- Adds brightness slider to settings tab
-- ═══════════════════════════════════════════════════════════════════════════════

local AIO = AIO or (require and require("AIO"))
if AIO and AIO.AddAddon and AIO.AddAddon() then return end

local PA = ProjectAstral
if not PA then return end

-- ── Brightness Module ──
PA.Brightness = PA.Brightness or {}
local Brightness = PA.Brightness

Brightness.value = 1.0
Brightness.min = 0.5
Brightness.max = 1.5
Brightness.registry = {}

-- Load saved brightness
do
    local settings = PA.Settings or {}
    if settings.globalBrightness then
        Brightness.value = math.max(Brightness.min,
            math.min(Brightness.max, tonumber(settings.globalBrightness) or 1.0))
    end
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Core Functions
-- ═══════════════════════════════════════════════════════════════════════════════

function Brightness.Brighten(color)
    if not color then return 1, 1, 1, 1 end
    return math.min(1.0, color[1] * Brightness.value),
           math.min(1.0, color[2] * Brightness.value),
           math.min(1.0, color[3] * Brightness.value),
           color[4] or 1.0
end

function Brightness.BrightenRGB(r, g, b, a)
    return math.min(1.0, r * Brightness.value),
           math.min(1.0, g * Brightness.value),
           math.min(1.0, b * Brightness.value),
           a or 1.0
end

function Brightness.SetBrightness(value)
    Brightness.value = math.max(Brightness.min, math.min(Brightness.max, value))
    if PA.SaveSetting then
        PA.SaveSetting("globalBrightness", Brightness.value)
    end
    Brightness.ApplyToAll()
end

function Brightness.GetBrightness()
    return Brightness.value
end

function Brightness.Register(id, applyFunc)
    if type(id) ~= "string" or type(applyFunc) ~= "function" then return end
    Brightness.registry[id] = applyFunc
end

function Brightness.Unregister(id)
    Brightness.registry[id] = nil
end

function Brightness.ApplyToAll()
    for id, applyFunc in pairs(Brightness.registry) do
        pcall(applyFunc)
    end
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Helper Functions
-- ═══════════════════════════════════════════════════════════════════════════════

function Brightness.ApplyToFontString(fontString, r, g, b, a)
    if not fontString or not fontString.SetTextColor then return end
    local br, bg, bb, ba = Brightness.BrightenRGB(r, g, b, a)
    fontString:SetTextColor(br, bg, bb, ba)
end

function Brightness.ApplyToTexture(texture, r, g, b, a)
    if not texture or not texture.SetVertexColor then return end
    local br, bg, bb, ba = Brightness.BrightenRGB(r, g, b, a)
    texture:SetVertexColor(br, bg, bb, ba)
end

function Brightness.ApplyToBackdrop(frame, bgColor, borderColor)
    if not frame or not frame.SetBackdropColor then return end

    if bgColor then
        local r, g, b, a = Brightness.Brighten(bgColor)
        frame:SetBackdropColor(r, g, b, a)
    end

    if borderColor and frame.SetBackdropBorderColor then
        local r, g, b, a = Brightness.Brighten(borderColor)
        frame:SetBackdropBorderColor(r, g, b, a)
    end
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Settings Tab Integration
-- ═══════════════════════════════════════════════════════════════════════════════

local function BuildBrightnessSettings(panel)
    if not panel then return end

    -- Title
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 20, -20)
    title:SetText("☀ UI Brightness")
    if PA.UI and PA.UI.Color and PA.UI.Color.textTitle then
        title:SetTextColor(Brightness.Brighten(PA.UI.Color.textTitle))
    else
        title:SetTextColor(0.9, 0.85, 1.0)
    end

    -- Description
    local desc = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    desc:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    desc:SetText("Adjust the brightness of all UI elements (except main tab)")
    desc:SetTextColor(0.6, 0.6, 0.7)

    -- Slider container
    local sliderContainer = CreateFrame("Frame", nil, panel)
    sliderContainer:SetSize(400, 30)
    sliderContainer:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -15)

    -- Slider
    local slider = CreateFrame("Slider", "PAGlobalBrightnessSlider", sliderContainer, "OptionsSliderTemplate")
    slider:SetWidth(300)
    slider:SetHeight(17)
    slider:SetPoint("LEFT", sliderContainer, "LEFT", 0, 0)
    slider:SetMinMaxValues(Brightness.min * 100, Brightness.max * 100)
    slider:SetValueStep(5)
    slider:SetValue(Brightness.value * 100)
    slider:SetOrientation("HORIZONTAL")

    -- Style slider
    local sliderName = slider:GetName()
    if sliderName then
        _G[sliderName .. "Text"]:SetText("")
        _G[sliderName .. "Low"]:SetText("50%")
        _G[sliderName .. "High"]:SetText("150%")
    end
    slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")

    -- Value display
    local valueText = sliderContainer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    valueText:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    valueText:SetPoint("LEFT", slider, "RIGHT", 10, 0)
    valueText:SetText(string.format("%.0f%%", Brightness.value * 100))
    valueText:SetTextColor(1.0, 0.95, 0.5)

    -- Slider callback
    slider:SetScript("OnValueChanged", function(self, val)
        local newValue = val / 100
        valueText:SetText(string.format("%.0f%%", val))
        Brightness.SetBrightness(newValue)
    end)

    -- Reset button
    local resetBtn = CreateFrame("Button", nil, sliderContainer, "UIPanelButtonTemplate")
    resetBtn:SetSize(60, 22)
    resetBtn:SetPoint("LEFT", valueText, "RIGHT", 10, 0)
    resetBtn:SetText("Reset")
    resetBtn:SetScript("OnClick", function()
        slider:SetValue(100)
        Brightness.SetBrightness(1.0)
    end)

    -- Store references
    panel.brightnessSlider = slider
    panel.brightnessValueText = valueText
end

-- Register as a settings tab
if PA.RegisterTabContent then
    PA:RegisterTabContent("Brightness", BuildBrightnessSettings)
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Initialization
-- ═══════════════════════════════════════════════════════════════════════════════

-- Apply brightness on load
Brightness.ApplyToAll()

print("|cff80e090[ProjectAstral] Brightness system loaded - check Settings tab|r")
