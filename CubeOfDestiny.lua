
local AIO = AIO or require("AIO")
if AIO.AddAddon() then return end

local PA = ProjectAstral
if not PA then return end
local UI = PA.UI

local lastPickup = nil
hooksecurefunc("PickupContainerItem", function(bag, slot)
    if not bag or not slot then return end
    lastPickup = {
        bag    = bag,
        slot   = slot,
        link   = GetContainerItemLink(bag, slot),
        itemID = GetContainerItemID and GetContainerItemID(bag, slot) or nil,
    }
end)
hooksecurefunc("ClearCursor", function() lastPickup = nil end)

local FRAME_W    = 340
local FRAME_H    = 340
local SLOT_SIZE  = 64

-- 2026-09-06 fix (poison/imbue replace-enchant taint bug):
-- The previous line here was:
--     StaticPopupDialogs = StaticPopupDialogs or {}
-- That is a GLOBAL re-assignment from insecure addon code. WoW's taint
-- system flags the global `StaticPopupDialogs` variable as tainted from
-- that moment onward. Blizzard's secure StaticPopup_Show later reads
-- StaticPopupDialogs["REPLACE_ENCHANT"] to render the "replace existing
-- enchant?" confirmation popup for poisons + shaman weapon imbues. The
-- read inherits the taint -> the popup's OnAccept function reference is
-- tainted -> when the user clicks Yes, the call to ReplaceEnchant()
-- (protected) is refused with "ProjectAstral has been blocked from an
-- action only available to the Blizzard UI".
--
-- Blizzard's FrameXML (Interface/FrameXML/StaticPopup.lua) defines the
-- StaticPopupDialogs global unconditionally at client load time, well
-- before any addon runs. The defensive `or {}` was never needed and
-- caused the taint. Simply omit it -- the assignment below writes to
-- an existing table (safe: key-level writes do not taint other keys).
StaticPopupDialogs["PA_CUBE_CONFIRM"] = {
    text          = "%s",
    button1       = "Re-roll",
    button2       = "Cancel",
    hasEditBox    = false,
    timeout       = 0,
    whileDead     = false,
    hideOnEscape  = true,
    exclusive     = true,
    OnAccept      = function() end,
}

local frame
local slotButton
local reserved = nil

local function SplitSuffix(fullName)
    if not fullName or fullName == "" then return "", "" end
    local last
    local start = 1
    while true do
        local s = fullName:find(" of ", start, true)
        if not s then break end
        last = s
        start = s + 1
    end
    if not last then return fullName, "" end
    return fullName:sub(1, last - 1), fullName:sub(last + 1)
end

local function UpdateNameLabel()
    if not frame or not frame.nameLabel then return end
    if not reserved or not reserved.link then
        frame.nameLabel:SetText("")
        return
    end
    local full = GetItemInfo(reserved.link)
    if not full then
        frame.nameLabel:SetText(reserved.link)
        return
    end
    local base, suffix = SplitSuffix(full)
    if suffix == "" then
        frame.nameLabel:SetText(base)
    else
        frame.nameLabel:SetFormattedText("%s |cffffd200%s|r", base, suffix)
    end
end

local function ClearReserved()
    reserved = nil
    if not slotButton then return end
    slotButton.icon:SetTexture("")
    if slotButton.emptyMark then slotButton.emptyMark:Show() end
    if frame and frame.rerollBtn then
        frame.rerollBtn:Disable()
        frame.rerollBtn:SetText("Re-roll (1 Orb of Destiny)")
    end
    if frame and frame.nameLabel then
        frame.nameLabel:SetText("")
    end
end

local function ResolveItemIcon(entry)
    if not entry then return "Interface\\Icons\\INV_Misc_QuestionMark" end
    local _, _, _, _, _, _, _, _, _, tex = GetItemInfo(entry)
    return tex or "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- What the cube will do with the item. Mythic items (suffix 2000..4999 in
-- link field 7) and legendaries are changed in place: gems, enchants and the
-- tier stay. A legendary without a suffix gets a random Mythic affix.
local function RerollKind(ref)
    local _, _, quality = GetItemInfo(ref.itemID)
    local suffix = tonumber(ref.link and ref.link:match(
        "|Hitem:[^:]*:[^:]*:[^:]*:[^:]*:[^:]*:[^:]*:(%-?%d+)")) or 0
    if suffix <= -2000 and suffix >= -4999 then return "mythic" end
    if quality == 5 then return "legendary" end
    return "normal"
end

local CONFIRM_TEXT = {
    legendary = "Give this legendary a random Mythic affix (tier I)?\n\n"
                .. "Gems and enchants stay on the item. From then on it can be upgraded.\n\n"
                .. "Cost: |cffffd2001 Orb of Destiny|r.",
    mythic    = "Re-roll the Mythic affix of this item?\n\n"
                .. "The tier, gems and enchants stay on the item.\n\n"
                .. "Cost: |cffffd2001 Orb of Destiny|r.",
    normal    = "Re-roll this item?\n\n"
                .. "|cffff6b6bAny gems and enchants on the item will be destroyed.|r\n"
                .. "|cffff6b6bThis action cannot be undone.|r\n\n"
                .. "Cost: |cffffd2001 Orb of Destiny|r.",
}

local function RerollButtonText(ref)
    if ref and RerollKind(ref) == "legendary" then
        return "Mythic affix (1 Orb of Destiny)"
    end
    return "Re-roll (1 Orb of Destiny)"
end

local function SetReserved(ref)
    reserved = {
        bag    = ref.bag,
        slot   = ref.slot,
        link   = ref.link,
        itemID = ref.itemID,
    }
    slotButton.icon:SetTexture(ResolveItemIcon(ref.itemID))
    if slotButton.emptyMark then slotButton.emptyMark:Hide() end
    if frame and frame.rerollBtn then
        frame.rerollBtn:Enable()
        frame.rerollBtn:SetText(RerollButtonText(ref))
    end
    UpdateNameLabel()
end

local function ValidateBeforeSubmit(ref)
    if not ref or not ref.itemID then return false, "No item picked up." end
    local _, _, quality, _, _, _, _, _, equipLoc = GetItemInfo(ref.itemID)
    if not equipLoc or equipLoc == "" then
        return false, "Item is not equippable."
    end
    if quality and (quality < 2 or quality > 5) then
        return false, "Only green, blue, purple, and legendary items can be re-rolled."
    end
    return true
end

local function Build()
    if frame then return end

    frame = CreateFrame("Frame", "ProjectAstralCubeOfDestiny", UIParent)
    frame:SetSize(FRAME_W, FRAME_H)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetFrameStrata("HIGH")
    frame:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile     = true, tileSize = 32, edgeSize = 32,
        insets   = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    PA.UI.CosmicCorners(frame)
    frame:SetBackdropColor(1, 1, 1, 1)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop",  frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)
    frame:Hide()

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    title:SetPoint("TOP", frame, "TOP", 0, -20)
    title:SetText("Cube of Destiny")
    if UI then title:SetTextColor(0.60, 0.85, 1.00) end
    title:SetShadowOffset(1, -1)
    title:SetShadowColor(0, 0, 0, 1)

    local orbLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    orbLabel:SetPoint("TOP", title, "BOTTOM", 0, -6)
    orbLabel:SetJustifyH("CENTER")
    orbLabel:SetTextColor(0.85, 0.80, 0.35)
    frame.orbLabel = orbLabel
    local function RefreshOrbLabel()
        orbLabel:SetText(("|cffffd200Orbs of Destiny|r  %d"):format(PA.orbs or 0))
    end
    RefreshOrbLabel()
    if PA.OnTokensChanged then
        PA:OnTokensChanged(function() if frame:IsShown() then RefreshOrbLabel() end end)
    end

    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    PA.UI.CosmicCloseButton(closeBtn)
    closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
    closeBtn:SetScript("OnClick", function()
        AIO.Handle("AstralCubeOfDestinyServer", "Close")
        frame:Hide()
        ClearReserved()
    end)

    local nameLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    nameLabel:SetPoint("BOTTOM", frame, "TOP", 0, -100)
    nameLabel:SetJustifyH("CENTER")
    nameLabel:SetWidth(FRAME_W - 30)
    nameLabel:SetText("")
    frame.nameLabel = nameLabel

    slotButton = CreateFrame("Button", "ProjectAstralCubeSlot", frame)
    slotButton:SetSize(SLOT_SIZE, SLOT_SIZE)
    slotButton:SetPoint("TOP", frame, "TOP", 0, -108)
    slotButton:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets   = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    PA.UI.CosmicCorners(slotButton)
    slotButton:SetBackdropColor(0.02, 0.03, 0.08, 0.95)
    slotButton:SetBackdropBorderColor(0.35, 0.55, 0.75, 1.0)

    local icon = slotButton:CreateTexture(nil, "ARTWORK")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:SetPoint("TOPLEFT",     slotButton, "TOPLEFT",      4, -4)
    icon:SetPoint("BOTTOMRIGHT", slotButton, "BOTTOMRIGHT", -4,  4)
    icon:SetTexture("")
    slotButton.icon = icon

    local empty = slotButton:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    empty:SetPoint("CENTER", slotButton, "CENTER", 0, 1)
    empty:SetText("+")
    empty:SetTextColor(0.35, 0.45, 0.55, 0.55)
    slotButton.emptyMark = empty

    slotButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    slotButton:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            ClearReserved()
            return
        end
        if CursorHasItem() and lastPickup then
            local ok, why = ValidateBeforeSubmit(lastPickup)
            if not ok then
                UIErrorsFrame:AddMessage(
                    "Cube of Destiny: " .. why, 1.0, 0.42, 0.42, 1.0)
                ClearCursor()
                return
            end
            SetReserved(lastPickup)
            ClearCursor()
            lastPickup = nil
        end
    end)
    slotButton:RegisterForDrag("LeftButton")
    slotButton:SetScript("OnReceiveDrag", function(self)
        if CursorHasItem() and lastPickup then
            local ok, why = ValidateBeforeSubmit(lastPickup)
            if not ok then
                UIErrorsFrame:AddMessage(
                    "Cube of Destiny: " .. why, 1.0, 0.42, 0.42, 1.0)
                ClearCursor()
                return
            end
            SetReserved(lastPickup)
            ClearCursor()
            lastPickup = nil
        end
    end)

    hooksecurefunc("PickupContainerItem", function(bag, slot)
        if not IsShiftKeyDown() then return end
        if not frame:IsShown() then return end
        if not CursorHasItem() then return end
        local ref = {
            bag    = bag,
            slot   = slot,
            link   = GetContainerItemLink(bag, slot),
            itemID = GetContainerItemID and GetContainerItemID(bag, slot) or nil,
        }
        local ok, why = ValidateBeforeSubmit(ref)
        if not ok then
            UIErrorsFrame:AddMessage(
                "Cube of Destiny: " .. why, 1.0, 0.42, 0.42, 1.0)
            ClearCursor()
            return
        end
        SetReserved(ref)
        ClearCursor()
    end)

    slotButton:SetScript("OnEnter", function(self)
        if reserved and reserved.link then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(reserved.link)
            GameTooltip:Show()
        else
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Empty slot")
            GameTooltip:AddLine("Pick up an item from your bag and click here, or shift-click.", 1, 1, 1, true)
            GameTooltip:AddLine("Right-click to clear.", 0.6, 0.6, 0.6, true)
            GameTooltip:Show()
        end
    end)
    slotButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local btn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    PA.UI.CosmicButton(btn)
    btn:SetSize(180, 28)
    btn:SetPoint("BOTTOM", frame, "BOTTOM", 0, 60)
    btn:SetText("Re-roll (1 Orb of Destiny)")
    btn:Disable()
    btn:SetScript("OnClick", function()
        if not reserved then return end
        local capturedBag  = reserved.bag
        local capturedSlot = reserved.slot
        StaticPopupDialogs["PA_CUBE_CONFIRM"].OnAccept = function()
            AIO.Handle("AstralCubeOfDestinyServer",
                       "Reroll", capturedBag, capturedSlot)
            btn:Disable()
            btn:SetText("Rolling...")
        end
        StaticPopup_Show("PA_CUBE_CONFIRM", CONFIRM_TEXT[RerollKind(reserved)])
    end)
    frame.rerollBtn = btn

    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("BOTTOM", btn, "TOP", 0, 12)
    hint:SetText("Cost: 1 Orb of Destiny. Item comes back with fresh random stats.\n"
        .. "|cffff6b6bWARNING:|r gems and enchants are destroyed (Mythic items and legendaries keep them).\n"
        .. "|cffff6b6bThis action cannot be undone.|r")
    hint:SetTextColor(0.60, 0.75, 0.90)
    hint:SetWidth(FRAME_W - 30)
    hint:SetJustifyH("CENTER")

    tinsert(UISpecialFrames, "ProjectAstralCubeOfDestiny")

    ClearReserved()
end

local ClientHandler = AIO.AddHandlers("AstralCubeOfDestiny", {})

ClientHandler.Open = function(_, orbs)
    Build()
    if orbs then PA.orbs = orbs end
    frame.orbLabel:SetText(("|cffffd200Orbs of Destiny|r  %d"):format(PA.orbs or 0))
    ClearReserved()
    frame:Show()
end

ClientHandler.Close = function()
    if frame then frame:Hide() end
    ClearReserved()
end

ClientHandler.OrbsUpdated = function(_, orbs)
    if orbs then PA.orbs = orbs end
    if frame and frame:IsShown() then
        frame.orbLabel:SetText(("|cffffd200Orbs of Destiny|r  %d"):format(PA.orbs or 0))
    end
end

ClientHandler.Result = function(_, ok, entry, orbs, reason)
    if orbs then PA.orbs = orbs end
    if frame and frame.rerollBtn then
        frame.rerollBtn:Enable()
        frame.rerollBtn:SetText("Re-roll (1 Orb of Destiny)")
    end
    if frame and frame.orbLabel then
        frame.orbLabel:SetText(("|cffffd200Orbs of Destiny|r  %d"):format(PA.orbs or 0))
    end

    if ok then
        UIErrorsFrame:AddMessage(
            "Cube of Destiny: item re-rolled!",
            0.55, 1.00, 0.55, 1.0)
        ClearReserved()
    else
        local reasonStr = ({
            NOT_OPEN          = "You must be at the cube.",
            NOT_AT_CUBE       = "You walked away from the cube.",
            ITEM_NOT_FOUND    = "Item missing from that slot.",
            NOT_EQUIPPABLE    = "Only equippable items can be re-rolled.",
            BAD_QUALITY       = "Only green, blue, purple, and legendary items can be re-rolled.",
            NO_RANDOM_ROLL    = "This item has no random stats to re-roll.",
            INSUFFICIENT_ORBS = "You don't have enough Orbs of Destiny.",
            ADDITEM_FAILED    = "Your bags are full — item was returned, orb refunded.",
        })[reason] or ("Re-roll rejected: " .. tostring(reason))
        UIErrorsFrame:AddMessage(
            "Cube of Destiny: " .. reasonStr,
            1.0, 0.42, 0.42, 1.0)
    end
end
