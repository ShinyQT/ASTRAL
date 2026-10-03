
local RADIUS = 80

local angle  = 225

local function LoadAngleFromSettings()
    if ProjectAstralSettings and type(ProjectAstralSettings.minimapAngle) == "number" then
        angle = ProjectAstralSettings.minimapAngle
        return
    end
    local sv = ProjectAstral and ProjectAstral.Settings
    if sv and type(sv.minimapAngle) == "number" then
        angle = sv.minimapAngle
    end
end

local function SaveAngle(a)
    angle = a
    ProjectAstralSettings = ProjectAstralSettings or {}
    ProjectAstralSettings.minimapAngle = a
    if ProjectAstral and ProjectAstral.SaveSetting then
        ProjectAstral.SaveSetting("minimapAngle", a)
    elseif ProjectAstral and ProjectAstral.Settings then
        ProjectAstral.Settings.minimapAngle = a
    end
end

local function UpdatePosition(btn)
    local rad = math.rad(angle)
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", Minimap, "CENTER",
        RADIUS * math.cos(rad),
        RADIUS * math.sin(rad))
end

local function CreateMinimapButton()
    local btn = CreateFrame("Button", "PAMinimapButton", Minimap)
    btn:SetSize(31, 31)
    btn:SetFrameLevel(100)
    btn:SetFrameStrata("MEDIUM")
    btn:EnableMouse(true)
    btn:RegisterForClicks("AnyUp")
    btn:RegisterForDrag("LeftButton")

    local icon = btn:CreateTexture(nil, "BACKGROUND")
    icon:SetAllPoints(btn)
    icon:SetTexture("Interface\\AddOns\\ProjectAstral\\astralhub")

    btn:SetHighlightTexture(
        "Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    LoadAngleFromSettings()
    UpdatePosition(btn)

    btn:SetScript("OnDragStart", function(self)
        self:LockHighlight()
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local s      = Minimap:GetEffectiveScale()
            angle = math.deg(math.atan2((cy / s) - my, (cx / s) - mx)) % 360
            UpdatePosition(self)
        end)
    end)

    btn:SetScript("OnDragStop", function(self)
        self:UnlockHighlight()
        self:SetScript("OnUpdate", nil)
        SaveAngle(angle)
    end)

    btn:SetScript("OnClick", function(_, button)
        if button == "LeftButton" then
            ProjectAstral:ToggleMainMenu()
        end
    end)

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Project Astral", 1, 0.82, 0, true)
        GameTooltip:AddLine("Open Astral systems menu.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

local evt = CreateFrame("Frame")
evt:RegisterEvent("PLAYER_LOGIN")
evt:SetScript("OnEvent", function()
    CreateMinimapButton()
end)

ProjectAstral.MinimapButton = ProjectAstral.MinimapButton or {}
function ProjectAstral.MinimapButton.SetVisible(visible)
    if PAMinimapButton then
        if visible then PAMinimapButton:Show() else PAMinimapButton:Hide() end
    end
end
