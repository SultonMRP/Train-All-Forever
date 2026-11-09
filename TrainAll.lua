local ADDON_NAME = ...

local Cost, created, TrainAllButton

-- Forever (and Classic) disagree on GetTrainerServiceInfo:
--   Classic: name, subName, status
--   Retail / Forever trainer UI: name, status
-- Pet trainers may also return an enum instead of the "available" string,
-- or leave status unset for skills the hunter already knows but the pet does not.
local STATUS = {
	available = "available",
	unavailable = "unavailable",
	used = "used",
	header = "header",
}

local function MapEnumStatus(enumTable)
	if type(enumTable) ~= "table" then
		return
	end
	for name, id in pairs(enumTable) do
		if type(name) == "string" and type(id) == "number" then
			STATUS[id] = strlower(name)
		end
	end
end

if Enum then
	MapEnumStatus(Enum.TrainerServiceState)
	MapEnumStatus(Enum.TrainerServiceType)
	MapEnumStatus(Enum.TrainerServiceStatus)
end

local function IsAddonLoaded(name)
	if C_AddOns and C_AddOns.IsAddOnLoaded then
		return C_AddOns.IsAddOnLoaded(name)
	end
	if _G.IsAddOnLoaded then
		return _G.IsAddOnLoaded(name)
	end
	return false
end

local function GetTrainButton()
	if ClassTrainerFrame and ClassTrainerFrame.TrainButton then
		return ClassTrainerFrame.TrainButton
	end
	return ClassTrainerTrainButton
end

local function IsPetTrainer()
	if C_Trainer and C_Trainer.GetTrainerType and Enum and Enum.TrainerType then
		local ok, trainerType = pcall(C_Trainer.GetTrainerType)
		if ok then
			return trainerType == Enum.TrainerType.Pet
		end
	end
	local points = ClassTrainerFrame and ClassTrainerFrame.trainingPoints
	return points and points.IsShown and points:IsShown()
end

local function GetServiceStatus(index)
	local info = { GetTrainerServiceInfo(index) }
	for i = 1, #info do
		local v = info[i]
		if type(v) == "string" then
			v = strlower(v)
		end
		if STATUS[v] then
			return STATUS[v]
		end
	end
end

local function ServiceCosts(index)
	local money, extra = GetTrainerServiceCost(index)
	money = money or 0
	-- Forever class/profession trainers: (money, isProfession)
	-- Classic pet trainers: (money, trainingPointCost)
	local isProfession = extra == true
	local points = type(extra) == "number" and extra or 0
	return money, points, isProfession
end

local function MoneyText(copper)
	if GetMoneyString then
		return GetMoneyString(copper)
	end
	if C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString then
		return C_CurrencyInfo.GetCoinTextureString(copper)
	end
	return tostring(copper or 0)
end

local function RemainingTrainingPoints()
	local fn = (C_PetInfo and C_PetInfo.GetPetTrainingPoints) or GetPetTrainingPoints
	if not fn then
		return nil
	end
	local ok, total, spent = pcall(fn)
	if not ok or total == nil then
		return nil
	end
	return (total or 0) - (spent or 0)
end

local function TrainerSpellID(index)
	if not C_TooltipInfo or not C_TooltipInfo.GetTrainerService then
		return
	end
	local ok, data = pcall(C_TooltipInfo.GetTrainerService, index)
	if ok and type(data) == "table" then
		return data.id
	end
end

local function IsPetSpellKnown(id)
	if not id then
		return false
	end
	if C_SpellBook and C_SpellBook.IsSpellKnown then
		local ok, known = pcall(C_SpellBook.IsSpellKnown, id, true)
		if ok and known then
			return true
		end
	end
	if IsSpellKnown and IsSpellKnown(id, true) then
		return true
	end
	return false
end

local function CanTrainService(index, money, points, petTrainer)
	local name = GetTrainerServiceInfo(index)
	local status = GetServiceStatus(index)
	if not name or status == "header" then
		return false, 0, 0
	end

	-- Profession "skill up" rows are purchased through the native Train button.
	if not petTrainer and GetTrainerServiceStepIndex then
		local step = GetTrainerServiceStepIndex()
		if step and index == step then
			return false, 0, 0
		end
	end

	local cost, pointCost, isProfession = ServiceCosts(index)
	if isProfession then
		return false, 0, 0
	end

	local available = status == "available"
	if not available and petTrainer then
		-- Forever pet lists often mark hunter-known skills as used/blank even when
		-- the current pet can still be taught. Skip only clearly unavailable rows.
		if status == "unavailable" then
			return false, 0, 0
		end
		if IsPetSpellKnown(TrainerSpellID(index)) then
			return false, 0, 0
		end
		available = true
	end
	if not available then
		return false, 0, 0
	end
	if cost > money then
		return false, cost, pointCost
	end
	if pointCost > 0 and points ~= nil and pointCost > points then
		return false, cost, pointCost
	end
	return true, cost, pointCost
end

-- BuyTrainerService is protected on Forever. It is only legal during the
-- same hardware click (mouse down). Timers and follow-up OnClick (mouse up)
-- are forbidden and trip BugGrabber.
local function TrainAll()
	local money = GetMoney and GetMoney() or 0
	local points = RemainingTrainingPoints()
	local petTrainer = IsPetTrainer()
	local n = GetNumTrainerServices() or 0
	for i = n, 1, -1 do
		local canTrain, cost, pointCost = CanTrainService(i, money, points, petTrainer)
		if canTrain then
			BuyTrainerService(i)
			money = money - cost
			if points and pointCost > 0 then
				points = points - pointCost
			end
		end
	end
end

local function UpdateButton()
	if not TrainAllButton then
		return
	end
	Cost = 0
	local enable = false
	local money = GetMoney and GetMoney() or 0
	local points = RemainingTrainingPoints()
	local petTrainer = IsPetTrainer()
	for i = 1, GetNumTrainerServices() or 0 do
		local canTrain, cost = CanTrainService(i, money, points, petTrainer)
		if canTrain then
			Cost = Cost + (cost or 0)
			enable = true
		end
	end
	if enable then
		TrainAllButton:Enable()
	else
		TrainAllButton:Disable()
	end
	TrainAllButton:Show()
end

local function createit()
	local trainButton = GetTrainButton()
	if not ClassTrainerFrame or not trainButton then
		return
	end
	if created then
		UpdateButton()
		return
	end
	created = true

	TrainAllButton = CreateFrame("Button", "TrainAllButton", ClassTrainerFrame, "MagicButtonTemplate")
	TrainAllButton:SetText("Train All")
	TrainAllButton:SetHeight(trainButton:GetHeight() or 22)
	TrainAllButton:SetPoint("RIGHT", trainButton, "LEFT", -1, 0)
	TrainAllButton:RegisterForClicks("LeftButtonDown", "LeftButtonUp")

	TrainAllButton:HookScript("OnShow", function()
		local anchor = GetTrainButton()
		if not anchor then
			return
		end
		TrainAllButton:ClearAllPoints()
		TrainAllButton:SetPoint("RIGHT", anchor, "LEFT", -1, 0)
	end)
	TrainAllButton:SetScript("OnEnter", function()
		GameTooltip:SetOwner(TrainAllButton, "ANCHOR_RIGHT")
		if IsPetTrainer() then
			GameTooltip:SetText("Train all available pet skills\nTotal cost is " .. MoneyText(Cost or 0))
		else
			GameTooltip:SetText("Train all available skills\nTotal cost is " .. MoneyText(Cost or 0))
		end
	end)
	TrainAllButton:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	TrainAllButton:SetScript("OnMouseDown", function(_, mouseButton)
		if mouseButton == "LeftButton" then
			TrainAll()
		end
	end)

	if IsAddonLoaded("ElvUI") and ElvUI then
		local ok, E = pcall(function()
			return unpack(ElvUI)
		end)
		if ok and E and E.GetModule then
			local S = E:GetModule("Skins")
			if S and S.HandleButton then
				S:HandleButton(TrainAllButton, 1)
			end
		end
	end

	if ClassTrainerFrame_Update then
		hooksecurefunc("ClassTrainerFrame_Update", UpdateButton)
	end
	if ClassTrainerFrame.Update then
		hooksecurefunc(ClassTrainerFrame, "Update", UpdateButton)
	end
	ClassTrainerFrame:HookScript("OnShow", UpdateButton)
	UpdateButton()
end

if EventUtil and EventUtil.ContinueOnAddOnLoaded then
	EventUtil.ContinueOnAddOnLoaded("Blizzard_TrainerUI", createit)
else
	local event = CreateFrame("Frame")
	event:RegisterEvent("ADDON_LOADED")
	event:SetScript("OnEvent", function(_, _, name)
		if name == "Blizzard_TrainerUI" or name == ADDON_NAME or name == "TrainAll" then
			if IsAddonLoaded("Blizzard_TrainerUI") then
				createit()
				event:UnregisterEvent("ADDON_LOADED")
			end
		end
	end)
end

local refresh = CreateFrame("Frame")
refresh:RegisterEvent("TRAINER_SHOW")
refresh:RegisterEvent("TRAINER_UPDATE")
refresh:RegisterEvent("TRAINER_SERVICE_INFO_NAME_UPDATE")
refresh:RegisterEvent("PLAYER_MONEY")
refresh:SetScript("OnEvent", function()
	createit()
	UpdateButton()
end)
