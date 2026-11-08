local ADDON_NAME = ...

local Cost, created

-- Forever (and Classic) disagree on GetTrainerServiceInfo:
--   Classic: name, subName, status
--   Retail / Forever trainer UI: name, status
local STATUS = {
	available = true,
	unavailable = true,
	used = true,
	header = true,
}

local function IsAddonLoaded(name)
	if C_AddOns and C_AddOns.IsAddOnLoaded then
		return C_AddOns.IsAddOnLoaded(name)
	end
	if _G.IsAddOnLoaded then
		return _G.IsAddOnLoaded(name)
	end
	return false
end

local function GetServiceInfo(index)
	local a, b, c, d = GetTrainerServiceInfo(index)
	if STATUS[b] then
		return b
	end
	if STATUS[c] then
		return c
	end
	if STATUS[d] then
		return d
	end
	if STATUS[a] then
		return a
	end
end

local function ServiceCost(index)
	return GetTrainerServiceCost(index) or 0
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

-- BuyTrainerService is protected on Forever. It is only legal during the
-- same hardware click (mouse down). Timers and follow-up OnClick (mouse up)
-- are forbidden and trip BugGrabber.
local function TrainAll()
	local money = GetMoney and GetMoney() or 0
	local n = GetNumTrainerServices() or 0
	for i = n, 1, -1 do
		if GetServiceInfo(i) == "available" then
			local cost = ServiceCost(i)
			if cost <= money then
				BuyTrainerService(i)
				money = money - cost
			end
		end
	end
end

local function createit()
	if created or not ClassTrainerFrame or not ClassTrainerTrainButton then
		return
	end
	created = true

	local TrainAllButton = CreateFrame("Button", "TrainAllButton", ClassTrainerFrame, "MagicButtonTemplate")
	TrainAllButton:SetText("Train All")
	TrainAllButton:SetHeight(ClassTrainerTrainButton:GetHeight() or 22)
	TrainAllButton:SetPoint("RIGHT", ClassTrainerTrainButton, "LEFT", -1, 0)
	TrainAllButton:RegisterForClicks("LeftButtonDown", "LeftButtonUp")

	TrainAllButton:HookScript("OnShow", function()
		local frameRight = ClassTrainerFrame:GetRight()
		local buttonRight = TrainAllButton:GetRight()
		if frameRight and buttonRight and buttonRight > frameRight then
			TrainAllButton:ClearAllPoints()
			TrainAllButton:SetPoint("RIGHT", ClassTrainerTrainButton, "LEFT", -1, 0)
		end
	end)
	TrainAllButton:SetScript("OnEnter", function()
		GameTooltip:SetOwner(TrainAllButton, "ANCHOR_RIGHT")
		GameTooltip:SetText("Train all available skills\nTotal cost is " .. MoneyText(Cost or 0))
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
		hooksecurefunc("ClassTrainerFrame_Update", function()
			Cost = 0
			local enable = false
			for i = 1, GetNumTrainerServices() or 0 do
				if GetServiceInfo(i) == "available" then
					Cost = Cost + ServiceCost(i)
					enable = true
				end
			end
			if enable then
				TrainAllButton:Enable()
			else
				TrainAllButton:Disable()
			end
		end)
	end
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
