--[[
    TipOff: автопринятие и автосдача заданий.
    - Принимает задания у NPC (окно задания, диалог, приветствие, сопровождение от группы).
    - Сдаёт выполненные, если не нужно выбирать награду (0 или 1 вариант) и не нужно отдавать золото.
    - Чёрный список заданий и опция "не брать серые задания".
    - Shift при разговоре с NPC временно отключает автоматику.
]]

local TipOff = TipOff
local L = LibStub("AceLocale-3.0"):GetLocale("TipOff")

local function Enabled(key)
    return TipOff.db and TipOff.db.profile[key] and not IsShiftKeyDown()
end

-- Задания, которые автоматика выбрала, но не смогла сдать (нужно золото или выбор награды).
-- Не выбираем их снова 2 минуты, чтобы диалог с NPC не зацикливался.
local stuck = {}
local function MarkStuck(title) if title then stuck[title] = GetTime() end end
local function IsStuck(title)
    local t = title and stuck[title]
    return t and GetTime() - t < 120
end

local function Skipped(title)
    return title and TipOff.db.profile.skipQuests[title]
end

local function CompletedQuestTitles()
    local done = {}
    for i = 1, GetNumQuestLogEntries() do
        local title, _, _, _, isHeader, _, isComplete = GetQuestLogTitle(i)
        if title and not isHeader and isComplete == 1 then done[title] = true end
    end
    return done
end

local function QuestLogFull()
    local _, numQuests = GetNumQuestLogEntries()
    return (numQuests or 0) >= (MAX_QUESTS or 25)
end

-- Разбирает список из GetGossip*Quests: в 3.3.5 на задание приходится
-- 5 значений у доступных (title, level, isTrivial, isDaily, isRepeatable)
-- и 4 у текущих (title, level, isTrivial, isComplete). Шаг вычисляем на случай кастомного клиента.
local function ParseGossip(count, ...)
    local list = {}
    if count == 0 then return list end
    local stride = math.max(1, math.floor(select("#", ...) / count))
    for i = 1, count do
        local base = (i - 1) * stride
        list[i] = {
            title = select(base + 1, ...),
            level = select(base + 2, ...),
            trivial = stride >= 3 and select(base + 3, ...) or nil,
            complete = stride >= 4 and select(base + 4, ...) or nil,
        }
    end
    return list
end

local function CanTakeAvailable(title, trivial)
    if Skipped(title) then return false end
    if trivial and TipOff.db.profile.skipTrivialQuests then return false end
    return true
end

local function OnGossipShow()
    if Enabled("autoTurnInQuests") then
        local done = CompletedQuestTitles()
        for i, q in ipairs(ParseGossip(GetNumGossipActiveQuests(), GetGossipActiveQuests())) do
            if (q.complete or done[q.title]) and not Skipped(q.title) and not IsStuck(q.title) then
                SelectGossipActiveQuest(i)
                return
            end
        end
    end
    if Enabled("autoAcceptQuests") and not QuestLogFull() then
        for i, q in ipairs(ParseGossip(GetNumGossipAvailableQuests(), GetGossipAvailableQuests())) do
            if CanTakeAvailable(q.title, q.trivial) then
                SelectGossipAvailableQuest(i)
                return
            end
        end
    end
end

local function OnQuestGreeting()
    if Enabled("autoTurnInQuests") then
        local done = CompletedQuestTitles()
        for i = 1, GetNumActiveQuests() do
            local title, isComplete = GetActiveTitle(i)
            if (isComplete or done[title]) and not Skipped(title) and not IsStuck(title) then
                SelectActiveQuest(i)
                return
            end
        end
    end
    if Enabled("autoAcceptQuests") and not QuestLogFull() then
        for i = 1, GetNumAvailableQuests() do
            local trivial = GetAvailableQuestInfo and GetAvailableQuestInfo(i)
            if CanTakeAvailable(GetAvailableTitle(i), trivial) then
                SelectAvailableQuest(i)
                return
            end
        end
    end
end

local frame = CreateFrame("Frame")
for _, e in ipairs({ "GOSSIP_SHOW", "QUEST_GREETING", "QUEST_DETAIL", "QUEST_ACCEPT_CONFIRM", "QUEST_PROGRESS", "QUEST_COMPLETE" }) do
    frame:RegisterEvent(e)
end
frame:SetScript("OnEvent", function(self, event)
    if event == "GOSSIP_SHOW" then
        OnGossipShow()
    elseif event == "QUEST_GREETING" then
        OnQuestGreeting()
    elseif event == "QUEST_DETAIL" then
        if Enabled("autoAcceptQuests") and not QuestLogFull() and not Skipped(GetTitleText()) then AcceptQuest() end
    elseif event == "QUEST_ACCEPT_CONFIRM" then
        -- Задание сопровождения от другого игрока: подтверждаем и прячем стандартное окно
        if Enabled("autoAcceptQuests") and not QuestLogFull() then
            ConfirmAcceptQuest()
            StaticPopup_Hide("QUEST_ACCEPT")
        end
    elseif event == "QUEST_PROGRESS" then
        if Enabled("autoTurnInQuests") and not Skipped(GetTitleText()) then
            if IsQuestCompletable() and (GetQuestMoneyToGet() or 0) == 0 then
                CompleteQuest()
            else
                MarkStuck(GetTitleText())
            end
        end
    elseif event == "QUEST_COMPLETE" then
        if Enabled("autoTurnInQuests") and not Skipped(GetTitleText()) then
            local choices = GetNumQuestChoices()
            if choices <= 1 then
                GetQuestReward(choices)
            else
                MarkStuck(GetTitleText()) -- награду выбирает игрок
            end
        end
    end
end)

---------------------------------------------------------------------------
-- Чёрный список
---------------------------------------------------------------------------
function TipOff:ToggleSkipQuest(title)
    if not title or title == "" then return end
    local list = self.db.profile.skipQuests
    if list[title] then
        list[title] = nil
        TipOff.Msg(string.format(L["MSG_SKIP_REMOVED"], title))
    else
        list[title] = true
        TipOff.Msg(string.format(L["MSG_SKIP_ADDED"], title))
    end
    if self.UpdateOptions then self:UpdateOptions() end
    if self.UpdateSkipButton then self:UpdateSkipButton() end
end

-- Маленькая кнопка в окне задания: "не брать / не сдавать автоматически"
local skipButton = CreateFrame("Button", "TipOffQuestSkipButton", QuestFrame, "UIPanelButtonTemplate")
skipButton:SetWidth(140)
skipButton:SetHeight(22)
skipButton:SetPoint("BOTTOM", QuestFrame, "BOTTOM", -8, 72)
skipButton:SetScript("OnClick", function() TipOff:ToggleSkipQuest(GetTitleText()) end)
skipButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("TipOff")
    GameTooltip:AddLine(L["SKIP_BUTTON_DESC"], 1, 1, 1, true)
    GameTooltip:Show()
end)
skipButton:SetScript("OnLeave", GameTooltip_Hide)
skipButton:Hide()

function TipOff:UpdateSkipButton()
    local p = self.db and self.db.profile
    if not p or not (p.autoAcceptQuests or p.autoTurnInQuests) or not QuestFrame:IsShown() then
        skipButton:Hide()
        return
    end
    skipButton:SetText(Skipped(GetTitleText()) and L["SKIP_BUTTON_UNDO"] or L["SKIP_BUTTON"])
    skipButton:Show()
end

QuestFrame:HookScript("OnHide", function() skipButton:Hide() end)

local buttonEvents = CreateFrame("Frame")
for _, e in ipairs({ "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE", "QUEST_FINISHED", "QUEST_GREETING" }) do
    buttonEvents:RegisterEvent(e)
end
buttonEvents:SetScript("OnEvent", function(self, event)
    if event == "QUEST_FINISHED" or event == "QUEST_GREETING" then
        skipButton:Hide()
    else
        TipOff:UpdateSkipButton()
    end
end)
