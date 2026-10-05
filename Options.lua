--[[
    TipOff: окно настроек с вкладками, панель в "Интерфейс → Модификации" и кнопка у миникарты.
]]

local TipOff = TipOff
local L = LibStub("AceLocale-3.0"):GetLocale("TipOff")

local ADDON_ICON = "Interface\\Icons\\INV_Scroll_03"
local VERSION = GetAddOnMetadata("TipOff", "Version") or ""
local WIDTH, HEIGHT = 470, 500
local KEYS = { "SHIFT", "CTRL", "ALT", "ALWAYS" }

local frame
local widgets = {}   -- всё, что нужно обновлять: { Update = fn }

local function Refresh()
    if not frame or not frame:IsShown() then return end
    for _, w in ipairs(widgets) do w:Update() end
end
TipOff.UpdateOptions = Refresh

---------------------------------------------------------------------------
-- Элементы
---------------------------------------------------------------------------
local checkCount = 0
local function CreateCheck(parent, key, label, desc, x, y, parentKey)
    checkCount = checkCount + 1
    local name = "TipOffOptionsCheck" .. checkCount
    local cb = CreateFrame("CheckButton", name, parent, "UICheckButtonTemplate")
    cb:SetWidth(26) cb:SetHeight(26)
    cb:SetPoint("TOPLEFT", x, y)
    local text = _G[name .. "Text"]
    text:SetFontObject(GameFontHighlight)
    text:SetText(L[label])
    text:ClearAllPoints()
    text:SetPoint("LEFT", cb, "RIGHT", 4, 1)
    cb:SetHitRectInsets(0, -280, 0, 0)
    cb:SetScript("OnClick", function(self)
        TipOff.db.profile[key] = self:GetChecked() and true or false
        PlaySound(self:GetChecked() and "igMainMenuOptionCheckBoxOn" or "igMainMenuOptionCheckBoxOff")
        if TipOff.UpdateSkipButton then TipOff:UpdateSkipButton() end
        Refresh()
    end)
    cb:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L[label], 1, 0.82, 0)
        GameTooltip:AddLine(L[desc], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    cb:SetScript("OnLeave", GameTooltip_Hide)
    function cb:Update()
        local p = TipOff.db.profile
        self:SetChecked(p[key] and true or false)
        if parentKey then
            if p[parentKey] then
                self:Enable() text:SetFontObject(GameFontHighlight)
            else
                self:Disable() text:SetFontObject(GameFontDisable)
            end
        end
    end
    widgets[#widgets + 1] = cb
    return cb
end

local function CreateHeader(parent, text, icon, y)
    local tex = parent:CreateTexture(nil, "ARTWORK")
    tex:SetWidth(16) tex:SetHeight(16)
    tex:SetPoint("TOPLEFT", 6, y)
    tex:SetTexture(icon)
    if icon:find("Icons") then tex:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
    local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    fs:SetPoint("LEFT", tex, "RIGHT", 6, 0)
    fs:SetText(L[text])
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetPoint("LEFT", fs, "RIGHT", 8, 0)
    line:SetPoint("RIGHT", parent, "RIGHT", -6, 0)
    line:SetTexture(1, 0.82, 0, 0.35)
end

local function CreateNote(parent, text, y, x)
    local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    fs:SetPoint("TOPLEFT", x or 12, y)
    fs:SetWidth(WIDTH - 70)
    fs:SetJustifyH("LEFT")
    fs:SetText(text)
    return fs
end

local function CreateButton(parent, text, width)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetWidth(width) b:SetHeight(22)
    b:SetText(text)
    return b
end

-- Список с прокруткой: строки + кнопка удаления, поле ввода + "Добавить"
local listCount = 0
local ROWS, ROW_H = 5, 18
local activeEditBoxes = {}

local function CreateList(parent, y, title, hint, getItems, onAdd, onRemove)
    listCount = listCount + 1
    local base = "TipOffOptionsList" .. listCount

    local label = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", 12, y)
    label:SetText(L[title])

    local edit = CreateFrame("EditBox", base .. "Edit", parent, "InputBoxTemplate")
    edit:SetWidth(WIDTH - 190) edit:SetHeight(20)
    edit:SetPoint("TOPLEFT", 18, y - 16)
    edit:SetAutoFocus(false)
    activeEditBoxes[#activeEditBoxes + 1] = edit
    local add = CreateButton(parent, L["BTN_ADD"], 100)
    add:SetPoint("LEFT", edit, "RIGHT", 8, 0)
    local function DoAdd()
        local text = strtrim(edit:GetText() or "")
        if text ~= "" then onAdd(text) end
        edit:SetText("")
        edit:ClearFocus()
    end
    add:SetScript("OnClick", DoAdd)
    edit:SetScript("OnEnterPressed", DoAdd)
    edit:SetScript("OnEscapePressed", edit.ClearFocus)

    local box = CreateFrame("Frame", nil, parent)
    box:SetPoint("TOPLEFT", 12, y - 42)
    box:SetWidth(WIDTH - 72) box:SetHeight(ROWS * ROW_H + 8)
    box:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    box:SetBackdropColor(0, 0, 0, 0.5)
    box:SetBackdropBorderColor(0.6, 0.6, 0.6, 0.8)

    local scroll = CreateFrame("ScrollFrame", base .. "Scroll", box, "FauxScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 4, -4)
    scroll:SetPoint("BOTTOMRIGHT", -26, 4)

    local empty = box:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    empty:SetPoint("CENTER")
    empty:SetText(L["LIST_EMPTY"])

    local rows = {}
    local list = { items = {} }
    for i = 1, ROWS do
        local row = CreateFrame("Button", nil, box)
        row:SetHeight(ROW_H)
        row:SetPoint("TOPLEFT", 8, -4 - (i - 1) * ROW_H)
        row:SetPoint("RIGHT", box, "RIGHT", -28, 0)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        row.text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        row.text:SetPoint("LEFT", 2, 0)
        row.text:SetPoint("RIGHT", -20, 0)
        row.text:SetJustifyH("LEFT")
        local del = CreateFrame("Button", nil, row, "UIPanelCloseButton")
        del:SetWidth(20) del:SetHeight(20)
        del:SetPoint("RIGHT", 2, 0)
        del:SetScript("OnClick", function() onRemove(row.key) end)
        rows[i] = row
    end

    function list:Update()
        self.items = getItems()
        local offset = FauxScrollFrame_GetOffset(scroll)
        for i = 1, ROWS do
            local item = self.items[offset + i]
            local row = rows[i]
            if item then
                row.key = item.key
                row.text:SetText(item.text)
                row:Show()
            else
                row:Hide()
            end
        end
        if #self.items == 0 then empty:Show() else empty:Hide() end
        FauxScrollFrame_Update(scroll, #self.items, ROWS, ROW_H)
    end
    scroll:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, ROW_H, function() list:Update() end)
    end)

    CreateNote(parent, L[hint], y - 42 - ROWS * ROW_H - 14)
    widgets[#widgets + 1] = list
    return list
end

-- Shift+клик по предмету вставляет ссылку в наше поле, если оно в фокусе
hooksecurefunc("ChatEdit_InsertLink", function(text)
    for _, e in ipairs(activeEditBoxes) do
        if e:HasFocus() and text then e:Insert(text) return end
    end
end)

---------------------------------------------------------------------------
-- Вкладки
---------------------------------------------------------------------------
local function BuildTooltipPage(page)
    CreateHeader(page, "SECTION_TOOLTIP_KEYS", "Interface\\Icons\\INV_Misc_Key_03", -4)

    local keyLabel = page:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    keyLabel:SetPoint("TOPLEFT", 14, -32)
    keyLabel:SetText(L["OPT_TOOLTIP_KEY"])
    local keyButton = CreateButton(page, "", 110)
    keyButton:SetPoint("LEFT", keyLabel, "RIGHT", 10, 0)
    keyButton:SetScript("OnClick", function()
        local p = TipOff.db.profile
        local idx = 1
        for i, k in ipairs(KEYS) do if k == p.tooltipKey then idx = i end end
        p.tooltipKey = KEYS[idx % #KEYS + 1]
        PlaySound("igMainMenuOptionCheckBoxOn")
        Refresh()
    end)
    keyButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["OPT_TOOLTIP_KEY"], 1, 0.82, 0)
        GameTooltip:AddLine(L["OPT_TOOLTIP_KEY_DESC"], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    keyButton:SetScript("OnLeave", GameTooltip_Hide)
    local expandNote = CreateNote(page, "", -56, 14)
    function keyButton:Update()
        local key = TipOff.db.profile.tooltipKey
        self:SetText(L["KEY_" .. key])
        expandNote:SetText(string.format(L["NOTE_EXPAND"], L["KEY_" .. TipOff:GetExpandKey()]))
    end
    widgets[#widgets + 1] = keyButton

    local slider = CreateFrame("Slider", "TipOffOptionsMaxLines", page, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", 20, -92)
    slider:SetWidth(WIDTH - 110)
    slider:SetMinMaxValues(0, 30)
    slider:SetValueStep(1)
    TipOffOptionsMaxLinesLow:SetText(L["SLIDER_NO_LIMIT"])
    TipOffOptionsMaxLinesHigh:SetText("30")
    local updating = false
    slider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value + 0.5)
        TipOffOptionsMaxLinesText:SetText(string.format(L["OPT_MAX_LINES"], value == 0 and L["SLIDER_NO_LIMIT"] or value))
        if not updating then TipOff.db.profile.maxLines = value end
    end)
    function slider:Update()
        local value = TipOff.db.profile.maxLines or 0
        updating = true
        self:SetValue(value)
        updating = false
        TipOffOptionsMaxLinesText:SetText(string.format(L["OPT_MAX_LINES"], value == 0 and L["SLIDER_NO_LIMIT"] or value))
    end
    widgets[#widgets + 1] = slider

    CreateHeader(page, "SECTION_TOOLTIP", "Interface\\Icons\\INV_Misc_Book_09", -130)
    local y = -154
    for _, o in ipairs({
        { "filterProfs", "OPT_PROFS", "OPT_PROFS_DESC" },
        { "markLearned", "OPT_LEARNED", "OPT_LEARNED_DESC" },
        { "filterUselessQuests", "OPT_QUESTS", "OPT_QUESTS_DESC" },
        { "filterFaction", "OPT_FACTION", "OPT_FACTION_DESC" },
        { "filterClass", "OPT_CLASS", "OPT_CLASS_DESC" },
    }) do
        CreateCheck(page, o[1], o[2], o[3], 10, y)
        y = y - 26
    end
    local learnedNote = CreateNote(page, "", y - 6)
    widgets[#widgets + 1] = { Update = function()
        learnedNote:SetText(string.format(L["NOTE_LEARNED"], TipOff:CountLearned()))
    end }
end

local function KeepItems()
    local items = {}
    for id, link in pairs(TipOff.db.profile.keepItems) do
        local text = type(link) == "string" and link or select(2, GetItemInfo(id)) or ("item:" .. id)
        items[#items + 1] = { key = id, text = text, sort = (GetItemInfo(id)) or tostring(id) }
    end
    table.sort(items, function(a, b) return a.sort < b.sort end)
    return items
end

local function BuildMerchantPage(page)
    CreateHeader(page, "SECTION_MERCHANT", "Interface\\Icons\\INV_Misc_Coin_01", -4)
    CreateCheck(page, "autoSellGray", "OPT_SELL", "OPT_SELL_DESC", 10, -28)
    CreateCheck(page, "autoRepair", "OPT_REPAIR", "OPT_REPAIR_DESC", 10, -54)
    CreateCheck(page, "guildRepair", "OPT_GUILD_REPAIR", "OPT_GUILD_REPAIR_DESC", 34, -80, "autoRepair")

    CreateHeader(page, "SECTION_KEEP", "Interface\\Icons\\INV_Misc_Bag_10", -118)
    CreateList(page, -142, "LIST_KEEP", "NOTE_KEEP", KeepItems,
        function(text)
            local id = tonumber(text:match("item:(%d+)") or text:match("^(%d+)$"))
            if not id then TipOff.Msg(L["MSG_BAD_ITEM"], true) return end
            local _, link = GetItemInfo(id)
            if not TipOff.db.profile.keepItems[id] then TipOff:ToggleKeepItem(link or ("item:" .. id)) end
        end,
        function(id)
            local v = TipOff.db.profile.keepItems[id]
            TipOff:ToggleKeepItem(type(v) == "string" and v or ("item:" .. id))
        end)
end

local function SkipQuests()
    local items = {}
    for title in pairs(TipOff.db.profile.skipQuests) do items[#items + 1] = { key = title, text = title } end
    table.sort(items, function(a, b) return a.text < b.text end)
    return items
end

local function BuildQuestsPage(page)
    CreateHeader(page, "SECTION_QUESTS", "Interface\\GossipFrame\\AvailableQuestIcon", -4)
    CreateCheck(page, "autoAcceptQuests", "OPT_AUTO_ACCEPT", "OPT_AUTO_ACCEPT_DESC", 10, -28)
    CreateCheck(page, "autoTurnInQuests", "OPT_AUTO_TURNIN", "OPT_AUTO_TURNIN_DESC", 10, -54)
    CreateCheck(page, "skipTrivialQuests", "OPT_SKIP_TRIVIAL", "OPT_SKIP_TRIVIAL_DESC", 10, -80)
    CreateNote(page, L["NOTE_SHIFT"], -110)

    CreateHeader(page, "SECTION_SKIP", "Interface\\Icons\\Ability_Rogue_Feint", -138)
    CreateList(page, -162, "LIST_SKIP", "NOTE_SKIP", SkipQuests,
        function(text) if not TipOff.db.profile.skipQuests[text] then TipOff:ToggleSkipQuest(text) end end,
        function(title) TipOff:ToggleSkipQuest(title) end)
end

local function BuildOtherPage(page)
    CreateHeader(page, "SECTION_OTHER", "Interface\\Icons\\INV_Misc_Gear_01", -4)
    local mm = CreateCheck(page, "__minimap", "OPT_MINIMAP", "OPT_MINIMAP_DESC", 10, -28)
    mm:SetScript("OnClick", function(self)
        TipOff.db.profile.minimap.hide = not self:GetChecked()
        TipOff:UpdateMinimapButton()
    end)
    function mm:Update() self:SetChecked(not TipOff.db.profile.minimap.hide) end

    local reset = CreateButton(page, L["BTN_RESET"], 180)
    reset:SetPoint("TOPLEFT", 14, -66)
    reset:SetScript("OnClick", function() StaticPopup_Show("TIPOFF_RESET") end)
    CreateNote(page, L["NOTE_RESET"], -94, 14)

    CreateHeader(page, "SECTION_ABOUT", ADDON_ICON, -130)
    CreateNote(page, string.format(L["ABOUT_TEXT"], VERSION), -154, 14)
end

StaticPopupDialogs["TIPOFF_RESET"] = {
    text = L["CONFIRM_RESET"],
    button1 = YES, button2 = NO,
    OnAccept = function()
        TipOff.db:ResetProfile()
        TipOff:UpdateMinimapButton()
        Refresh()
    end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

---------------------------------------------------------------------------
-- Окно
---------------------------------------------------------------------------
local TABS = {
    { "TAB_TOOLTIP", BuildTooltipPage },
    { "TAB_MERCHANT", BuildMerchantPage },
    { "TAB_QUESTS", BuildQuestsPage },
    { "TAB_OTHER", BuildOtherPage },
}

local function SelectTab(index)
    for i, t in ipairs(frame.tabs) do
        if i == index then
            t.button:LockHighlight()
            t.button:GetFontString():SetTextColor(1, 1, 1)
            t.page:Show()
        else
            t.button:UnlockHighlight()
            t.button:GetFontString():SetTextColor(1, 0.82, 0)
            t.page:Hide()
        end
    end
    frame.selected = index
    Refresh()
end

local function CreateOptionsFrame()
    frame = CreateFrame("Frame", "TipOffOptionsFrame", UIParent)
    frame:SetWidth(WIDTH) frame:SetHeight(HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    frame:Hide()
    tinsert(UISpecialFrames, "TipOffOptionsFrame")

    local header = frame:CreateTexture(nil, "ARTWORK")
    header:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
    header:SetWidth(280) header:SetHeight(64)
    header:SetPoint("TOP", 0, 12)
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", header, "TOP", 0, -14)
    title:SetText("|T" .. ADDON_ICON .. ":16|t TipOff |cff888888v" .. VERSION .. "|r")

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)

    local subtitle = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    subtitle:SetPoint("TOP", 0, -30)
    subtitle:SetTextColor(0.75, 0.75, 0.75)
    subtitle:SetText(L["OPTIONS_SUBTITLE"])

    frame.tabs = {}
    local tabWidth = math.floor((WIDTH - 40) / #TABS)
    for i, t in ipairs(TABS) do
        local b = CreateButton(frame, L[t[1]], tabWidth - 4)
        b:SetPoint("TOPLEFT", 20 + (i - 1) * tabWidth, -50)
        b:SetScript("OnClick", function() PlaySound("igCharacterInfoTab") SelectTab(i) end)
        local page = CreateFrame("Frame", nil, frame)
        page:SetPoint("TOPLEFT", 20, -84)
        page:SetPoint("BOTTOMRIGHT", -20, 50)
        page:Hide()
        t[2](page)
        frame.tabs[i] = { button = b, page = page }
    end

    local ok = CreateButton(frame, CLOSE or "OK", 110)
    ok:SetPoint("BOTTOMRIGHT", -20, 18)
    ok:SetScript("OnClick", function() frame:Hide() end)

    frame:SetScript("OnShow", function() PlaySound("igCharacterInfoOpen") Refresh() end)
    frame:SetScript("OnHide", function() PlaySound("igCharacterInfoClose") end)
    SelectTab(1)
end

function TipOff:ToggleOptions()
    if not frame then CreateOptionsFrame() end
    if frame:IsShown() then frame:Hide() else frame:Show() end
end

---------------------------------------------------------------------------
-- Панель в "Интерфейс → Модификации"
---------------------------------------------------------------------------
local function CreateBlizzardPanel()
    local panel = CreateFrame("Frame", "TipOffBlizzPanel", UIParent)
    panel.name = "TipOff"
    local t = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    t:SetPoint("TOPLEFT", 16, -16)
    t:SetText("|T" .. ADDON_ICON .. ":20|t TipOff")
    local d = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    d:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -8)
    d:SetWidth(380) d:SetJustifyH("LEFT")
    d:SetText(L["OPTIONS_SUBTITLE"])
    local b = CreateButton(panel, L["BTN_OPEN_OPTIONS"], 200)
    b:SetPoint("TOPLEFT", d, "BOTTOMLEFT", 0, -16)
    b:SetScript("OnClick", function()
        if InterfaceOptionsFrame then InterfaceOptionsFrame:Hide() end
        if GameMenuFrame then HideUIPanel(GameMenuFrame) end
        TipOff:ToggleOptions()
    end)
    InterfaceOptions_AddCategory(panel)
end

---------------------------------------------------------------------------
-- Кнопка у миникарты
---------------------------------------------------------------------------
local minimapButton

local function UpdateMinimapPosition()
    local angle = math.rad(TipOff.db.profile.minimap.angle or 200)
    minimapButton:ClearAllPoints()
    minimapButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * 80, math.sin(angle) * 80)
end

local function CreateMinimapButton()
    local b = CreateFrame("Button", "TipOffMinimapButton", Minimap)
    b:SetWidth(31) b:SetHeight(31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local icon = b:CreateTexture(nil, "BACKGROUND")
    icon:SetWidth(20) icon:SetHeight(20)
    icon:SetPoint("TOPLEFT", 7, -5)
    icon:SetTexture(ADDON_ICON)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetWidth(53) border:SetHeight(53)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    b:SetScript("OnClick", function() TipOff:ToggleOptions() end)
    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            TipOff.db.profile.minimap.angle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
            UpdateMinimapPosition()
        end)
    end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("TipOff")
        GameTooltip:AddLine(L["MINIMAP_TOOLTIP"], 1, 1, 1)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    minimapButton = b
end

function TipOff:UpdateMinimapButton()
    if not minimapButton then CreateMinimapButton() end
    if self.db.profile.minimap.hide then
        minimapButton:Hide()
    else
        UpdateMinimapPosition()
        minimapButton:Show()
    end
end

function TipOff:OnEnable()
    CreateBlizzardPanel()
    self:UpdateMinimapButton()
end
