if (select(6, GetAddOnInfo("ElvUI")) and select(6, GetAddOnInfo("TukUI"))) then
	return
end

local function SkinFrame(frame, template, override, kill)
	if not template then template = 'Transparent' end
	if not override then frame:StripTextures(kill) end
	frame:SetTemplate(template)
	--AS:RegisterForPetBattleHide(frame)
end

local frame = CreateFrame("frame")
frame:SetScript("OnUpdate", function()
	if FALootFrame then
	  local UI = FALoot.UI;
		SkinFrame(UI.itemWindow.frame)
		--SkinFrame(FALootTellsFrame)
		--SkinFrame(FALootFoodFrame)
		--SkinFrame(FALootDebugFrame)
		
		--FALootFrameStatusBar:SetTemplate("Default", true)
		
		UI.itemWindow.closeButton:SetTemplate("Default", true)
		UI.itemWindow.bidButton:SetTemplate("Default", true)
		UI.itemWindow.tellsButton:SetTemplate("Default", true)
		--FALootTellsFrameAwardButton:SetTemplate("Default", true)
		--FALootTellsFrameActionButton:SetTemplate("Default", true)
		--FALootFoodFrameButton:SetTemplate("Default", true)
		--FALootFoodFrameButton2:SetTemplate("Default", true)
		--FALootDebugFrameRefreshButton:SetTemplate("Default", true)
		--FALootDebugFrameCloseButton:SetTemplate("Default", true)
		--FALootDebugFrameEditBox:SetTemplate("Default", true)
		
		frame:SetScript("OnUpdate", nil)
	end
end)