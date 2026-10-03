
local PA = ProjectAstral
local UI = PA.UI

-- Gem Builds tab: save gem loadouts by name and load them again later, on any
-- character on the account (ProjectAstralGemBuilds is account-wide). Loading uses
-- the same one-click import as Astral Gems (AG.ApplyLoadoutText): gems come from the
-- Gem Stash (lower tiers if needed) and gems in the way are unsocketed first.
-- Each build shows whether you own all of its gems (AG.LoadoutGemStatus).

local ROW_H    = 66
local NUM_ROWS = 10
local CONFIRM_WINDOW = 3   -- seconds to click Delete a second time

local GREEN, YELLOW, RED = "|cff80e090", "|cffffcc66", "|cffff6060"

local host
local rows = {}
local RefreshList
local exportDialog, importDialog

local function DB()
    ProjectAstralGemBuilds = ProjectAstralGemBuilds or {}
    ProjectAstralGemBuilds.builds = ProjectAstralGemBuilds.builds or {}
    return ProjectAstralGemBuilds.builds
end

local function Gems() return PA.AstralGems end

local function Trim(s)
    return ((s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function SortedBuilds()
    local list = {}
    for _, b in ipairs(DB()) do list[#list + 1] = b end
    table.sort(list, function(a, b) return (a.savedAt or 0) > (b.savedAt or 0) end)
    return list
end

local function FindBuild(name)
    local lower = name:lower()
    for i, b in ipairs(DB()) do
        if (b.name or ""):lower() == lower then return b, i end
    end
end

local function SetStatus(text, color)
    if not host then return end
    host.status:SetText((color or "|cffaaaaaa") .. text .. "|r")
end

-- ── Do you have the gems? ───────────────────────────────────────────
local function GemStatus(b)
    local G = Gems()
    return G and G.LoadoutGemStatus and b and G.LoadoutGemStatus(b.text)
end

-- short, for the build row
local function ShortAvailability(st, count)
    if not st or st.total == 0 then
        return string.format("%d gem%s", count or 0, (count == 1) and "" or "s")
    end
    if st.missing > 0 then
        return string.format("%s%d/%d gems, %d missing|r", RED, st.exact + st.lower, st.total, st.missing)
    elseif st.lower > 0 then
        return string.format("%s%d/%d gems, %d at a lower tier|r", YELLOW, st.total, st.total, st.lower)
    end
    return string.format("%sAll %d gems owned|r", GREEN, st.total)
end

-- a sentence, for loading a build
local function LongAvailability(st)
    if not st or st.total == 0 then return nil end
    if st.missing == 0 and st.lower == 0 then
        return string.format("%sYou have all %d gems for this build.|r", GREEN, st.total)
    end
    local extra = {}
    if st.lower > 0 then extra[#extra + 1] = st.lower .. " more only at a lower tier" end
    if st.missing > 0 then extra[#extra + 1] = st.missing .. " missing" end
    return string.format("%sYou have %d of the %d gems (%s).|r",
        st.missing > 0 and RED or YELLOW, st.exact, st.total, table.concat(extra, ", "))
end

local function SaveCurrent()
    local G = Gems()
    if not (host and G and G.EncodeLoadout) then return end
    local name = Trim(host.nameBox:GetText())
    if name == "" then
        SetStatus("Type a name for this build first.", YELLOW)
        host.nameBox.edit:SetFocus()
        return
    end
    local text, count = G.EncodeLoadout()
    if count == 0 then
        SetStatus("No gems are socketed, so there's nothing to save.", YELLOW)
        return
    end

    local existing = FindBuild(name)
    local build = existing or {}
    local className, classFile = UnitClass("player")
    build.name, build.text, build.count = name, text, count
    build.savedBy, build.class, build.classFile = UnitName("player"), className, classFile
    build.savedAt, build.date = time(), date("%Y-%m-%d")
    if not existing then table.insert(DB(), build) end

    host.nameBox:Clear()
    host.nameBox.edit:ClearFocus()
    SetStatus(string.format("%s build '%s' (%d gem%s).", existing and "Updated" or "Saved",
        name, count, count == 1 and "" or "s"), GREEN)
    RefreshList()
end

local function LoadBuild(b)
    local G = Gems()
    if not (G and G.ApplyLoadoutText and G.DescribeLoadoutText) then return end
    if G.IsApplyingLoadout and G.IsApplyingLoadout() then
        SetStatus("A gem build is already being applied. Wait for it to finish.", YELLOW)
        return
    end
    local desc, fillCount = G.DescribeLoadoutText(b.text)
    if not desc then
        SetStatus("That build's data is damaged and can't be loaded.", RED)
        return
    end
    local avail = LongAvailability(GemStatus(b))
    if avail then
        DEFAULT_CHAT_FRAME:AddMessage("|cffa335ee[Gem Builds]|r '" .. b.name .. "': " .. avail)
    end
    if (fillCount or 0) == 0 then
        SetStatus((avail and (avail .. "  ") or "") .. desc)   -- nothing to socket: say why
        return
    end
    DEFAULT_CHAT_FRAME:AddMessage("|cffa335ee[Gem Builds]|r '" .. b.name .. "': " .. desc)
    SetStatus((avail and (avail .. "  ") or "") .. "Loading '" .. b.name .. "': " .. desc)
    G.ApplyLoadoutText(b.text)
end

local function DeleteBuild(b)
    for i, other in ipairs(DB()) do
        if other == b then
            table.remove(DB(), i)
            SetStatus("Deleted build '" .. (b.name or "?") .. "'.", YELLOW)
            RefreshList()
            return
        end
    end
end

local function ShowExport(b)
    if not UI.MakeTextDialog then return end
    if not exportDialog then
        exportDialog = UI.MakeTextDialog({
            name         = "PAGemBuildExportDialog",
            title        = "Export Gem Build",
            subtitle     = "Ctrl+A to select all, Ctrl+C to copy, then share it.",
            button1Label = "Close",
        })
    end
    exportDialog.header.title:SetText("Export: " .. (b.name or "?"))
    exportDialog:Show()
    exportDialog.editBox:SetText(b.text or "")
    exportDialog.editBox:HighlightText()
    exportDialog.editBox:SetFocus()
    exportDialog.status:SetText(string.format("%d gem%s, saved by %s on %s.",
        b.count or 0, (b.count == 1) and "" or "s", b.savedBy or "?", b.date or "?"))
end

local function ShowImport()
    if not UI.MakeTextDialog then return end
    if not importDialog then
        importDialog = UI.MakeTextDialog({
            name         = "PAGemBuildImportDialog",
            title        = "Import Gem Build",
            subtitle     = "Paste a gem loadout (AGEMS:1:...) to save it as a build.",
            button1Label = "Save Build",
            onAccept     = function(text, dlg)
                local G = Gems()
                local wanted = G and G.DecodeLoadout and G.DecodeLoadout(text)
                if not wanted or #wanted == 0 then
                    dlg.status:SetText(RED .. "That isn't a gem loadout (it should start with AGEMS:1:).|r")
                    return true
                end
                -- use the name typed in the tab, if any; never overwrite an existing build
                local base = Trim(host and host.nameBox:GetText() or "")
                if base == "" then base = "Imported build" end
                local name, n = base, 2
                while FindBuild(name) do
                    name = base .. " (" .. n .. ")"
                    n = n + 1
                end
                table.insert(DB(), {
                    name = name, text = (text:gsub("%s+", "")), count = #wanted,
                    savedBy = "Imported", savedAt = time(), date = date("%Y-%m-%d"),
                })
                if host then host.nameBox:Clear() end
                SetStatus("Imported build '" .. name .. "'.", GREEN)
                RefreshList()
                return false
            end,
        })
    end
    importDialog.status:SetText("Tip: type a name in the Gem Builds tab first to name the imported build.")
    importDialog.editBox:SetText("")
    importDialog:Show()
    importDialog.editBox:SetFocus()
end

local STATUS_COLOR = {
    exact   = { 1.00, 1.00, 1.00 },
    lower   = { 1.00, 0.80, 0.40 },
    missing = { 1.00, 0.38, 0.38 },
}
local STATUS_SUFFIX = { lower = "  (lower tier)", missing = "  (missing)" }

local function ShowPreview(row)
    local b = row.build
    if not b then return end
    local G = Gems()
    local schema  = (G and G.SLOT_SCHEMA) or {}
    local catalog = (PA.GemFusion and PA.GemFusion.catalog) or {}
    local st = GemStatus(b)

    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:AddLine(b.name or "?", 1, 1, 1)
    GameTooltip:AddLine(string.format("Saved by %s%s on %s", b.savedBy or "?",
        b.class and (" (" .. b.class .. ")") or "", b.date or "?"), 0.6, 0.6, 0.6)
    local avail = LongAvailability(st)
    if avail then GameTooltip:AddLine(avail, 1, 1, 1, true) end
    GameTooltip:AddLine(" ")
    for i, w in ipairs((G and G.DecodeLoadout and G.DecodeLoadout(b.text)) or {}) do
        if PA.ItemCache then PA.ItemCache.Register(w.entry) end
        local slot = schema[w.ord + 1]
        local cat  = catalog[w.entry]
        local name = GetItemInfo(w.entry)
                  or (cat and cat.name ~= "" and cat.name)
                  or ("Gem " .. w.entry)
        local state = st and st.byIndex[i]
        local c = STATUS_COLOR[state] or STATUS_COLOR.exact
        GameTooltip:AddDoubleLine(slot and slot.label or "?",
            name .. ((cat and cat.tier) and ("  T" .. cat.tier) or "") .. (STATUS_SUFFIX[state] or ""),
            0.7, 0.7, 0.7, c[1], c[2], c[3])
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Load swaps this build's gems in from your Gem Stash (removing gems that are in the way), using a lower tier of a gem when you don't have the exact one.",
        0.5, 0.8, 0.5, true)
    GameTooltip:Show()
end

local function CreateRow(parent, i)
    local r = CreateFrame("Button", nil, parent)
    r:SetHeight(ROW_H - 4)
    r:SetPoint("TOPLEFT",  parent, "TOPLEFT",  0, -((i - 1) * ROW_H))
    r:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -((i - 1) * ROW_H))
    UI.MakeRowChrome(r, { alt = (i % 2 == 0) })
    r:HookScript("OnEnter", ShowPreview)
    r:HookScript("OnLeave", function() GameTooltip:Hide() end)

    r.iconFrame = UI.MakeIconFrame(r, { size = 42 })
    r.iconFrame:SetPoint("LEFT", r, "LEFT", 8, 0)

    r.del = UI.MakeButton(r, "Delete", {
        w = 76, h = 30, variant = "danger",
        onClick = function()
            local b = r.build
            if not b then return end
            if r._confirmAt and GetTime() - r._confirmAt <= CONFIRM_WINDOW then
                DeleteBuild(b)
            else
                r._confirmAt = GetTime()
                r.del:SetLabel("Sure?")
                SetStatus("Click Sure? to delete '" .. (b.name or "?") .. "'.", YELLOW)
            end
        end,
    })
    r.del.text:SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE")
    r.del:SetPoint("RIGHT", r, "RIGHT", -6, 0)

    r.export = UI.MakeButton(r, "Export", {
        w = 76, h = 30, variant = "secondary",
        onClick = function() if r.build then ShowExport(r.build) end end,
    })
    r.export.text:SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE")
    r.export:SetPoint("RIGHT", r.del, "LEFT", -6, 0)

    r.load = UI.MakeButton(r, "Load", {
        w = 76, h = 30, variant = "primary",
        onClick = function() if r.build then LoadBuild(r.build) end end,
    })
    r.load.text:SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE")
    r.load:SetPoint("RIGHT", r.export, "LEFT", -6, 0)

    r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    r.name:SetFont("Fonts\\FRIZQT__.TTF", 16, "OUTLINE")
    r.name:SetPoint("TOPLEFT", r.iconFrame, "TOPRIGHT", 10, -1)
    r.name:SetPoint("RIGHT",   r.load,      "LEFT",    -8, 0)
    r.name:SetJustifyH("LEFT")
    if r.name.SetWordWrap then r.name:SetWordWrap(false) end

    r.sub = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    r.sub:SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE")
    r.sub:SetPoint("BOTTOMLEFT", r.iconFrame, "BOTTOMRIGHT", 10, 1)
    r.sub:SetPoint("RIGHT",      r.load,      "LEFT",       -8, 0)
    r.sub:SetJustifyH("LEFT")
    if r.sub.SetWordWrap then r.sub:SetWordWrap(false) end

    r:Hide()
    return r
end

RefreshList = function()
    if not host then return end
    local G = Gems()
    local list = SortedBuilds()
    local offset = FauxScrollFrame_GetOffset(host.scroll)

    for i = 1, NUM_ROWS do
        local r = rows[i]
        local b = list[i + offset]
        r.build = b
        r._confirmAt = nil
        r.del:SetLabel("Delete")
        if b then
            r.name:SetText(b.name or "?")
            r.sub:SetText(string.format("%s  ·  %s%s  ·  %s", ShortAvailability(GemStatus(b), b.count),
                b.savedBy or "?", b.class and (" (" .. b.class .. ")") or "", b.date or ""))
            local first = G and G.DecodeLoadout and (G.DecodeLoadout(b.text) or {})[1]
            local texture = first and select(10, GetItemInfo(first.entry))
            r.iconFrame:SetTexture(texture or "Interface\\Icons\\INV_Misc_Gem_Variety_01")
            r:Show()
        else
            r:Hide()
        end
    end

    FauxScrollFrame_Update(host.scroll, #list, NUM_ROWS, ROW_H)
    host.countLabel:SetText("Saved builds (" .. #list .. ")")
    if #list == 0 then host.empty:Show() else host.empty:Hide() end
end

local function AddTip(btn, title, body)
    btn:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(title, 1, 1, 1)
        GameTooltip:AddLine(body, 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    btn:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

local function BuildGemBuildsTab(panel)
    host = panel

    local nameBox = UI.MakeSearchBox(panel, {
        width = 340, height = 36, fontSize = 14,
        placeholder = "Name this build…",
    })
    nameBox:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -4)
    nameBox.edit:SetScript("OnEnterPressed", function() SaveCurrent() end)
    panel.nameBox = nameBox

    local saveBtn = UI.MakeButton(panel, "Save Current", {
        w = 150, h = 36, variant = "primary", onClick = function() SaveCurrent() end,
    })
    saveBtn.text:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
    saveBtn:SetPoint("LEFT", nameBox, "RIGHT", 8, 0)
    AddTip(saveBtn, "Save Current Gems",
        "Saves the gems socketed right now under the name you typed. Saving with an existing name updates that build.")

    local importBtn = UI.MakeButton(panel, "Import", {
        w = 100, h = 36, variant = "secondary", onClick = function() ShowImport() end,
    })
    importBtn.text:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
    importBtn:SetPoint("LEFT", saveBtn, "RIGHT", 6, 0)
    AddTip(importBtn, "Import Gem Build",
        "Paste a gem loadout someone shared (AGEMS:1:...) and save it as a build.")

    panel.status = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.status:SetPoint("TOPLEFT",  nameBox, "BOTTOMLEFT", 2, -8)
    panel.status:SetPoint("TOPRIGHT", panel,   "TOPRIGHT",  -4, -48)
    panel.status:SetHeight(32)
    panel.status:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
    panel.status:SetJustifyH("LEFT")
    panel.status:SetJustifyV("TOP")
    panel.status:SetTextColor(unpack(UI.Color.textMuted))
    panel.status:SetText("Socket your gems, name the build and click Save Current. "
        .. "Builds are shared by every character on your account.")

    panel.countLabel = UI.MakeSectionLabel(panel, "Saved builds")
    panel.countLabel.label:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
    panel.countLabel:SetPoint("TOPLEFT",  panel, "TOPLEFT",  0, -88)
    panel.countLabel:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, -88)

    local scroll = CreateFrame("ScrollFrame", "PAGemBuildsScroll", panel, "FauxScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",     panel, "TOPLEFT",     0, -108)
    scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -24, 0)
    scroll:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, ROW_H, RefreshList)
    end)
    panel.scroll = scroll

    local listFrame = CreateFrame("Frame", nil, panel)
    listFrame:SetPoint("TOPLEFT",     scroll, "TOPLEFT",     0, 0)
    listFrame:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 0, 0)
    for i = 1, NUM_ROWS do rows[i] = CreateRow(listFrame, i) end

    panel.empty = listFrame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    panel.empty:SetFont("Fonts\\FRIZQT__.TTF", 15, "OUTLINE")
    panel.empty:SetPoint("TOP", listFrame, "TOP", 0, -30)
    panel.empty:SetText("No gem builds saved yet.")

    panel:SetScript("OnShow", function()
        -- the stash may not have arrived yet; ask for it so "owned" counts are current
        if PA.GemStash and PA.GemStash.RequestState then PA.GemStash.RequestState() end
        RefreshList()
    end)

    -- owned counts follow the stash
    if PA.GemStash and PA.GemStash.OnStockChanged then
        PA.GemStash.OnStockChanged(function()
            if host and host:IsVisible() then RefreshList() end
        end)
    end
end

local function ToggleGemBuilds()
    local mf = PA.mainFrame
    if not mf then return end
    if mf:IsShown() and mf._activeTabId == "gem_builds" then
        mf:Hide()
    else
        mf:Show()
        mf:SwitchTab("gem_builds")
    end
end

PA:RegisterModule("gem_builds", "Gem Builds", ToggleGemBuilds, {
    subtitle = "Save gem loadouts and load them on any of your characters.",
})
PA:RegisterTabContent("gem_builds", BuildGemBuildsTab)
