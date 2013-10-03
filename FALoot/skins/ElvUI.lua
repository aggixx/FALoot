if select(6, GetAddOnInfo("ElvUI")) or select(6, GetAddOnInfo("ElvUI_AddonSkins")) then
	return
end

local frame = CreateFrame("frame")
frame:SetScript("OnUpdate", function()
	if FALootFrame then
		local E, L, V, P, G, _ = unpack(ElvUI)
		local AS = ElvUI[1]:GetModule('AddOnSkins')

		AS:SkinFrame(FALootFrame)
		AS:SkinFrame(FALootTellsFrame)
		
		FALootFrameStatusBar:SetTemplate("Default", true)
		
		FALootFrameCloseButton:SetTemplate("Default", true)
		FALootFrameBidButton:SetTemplate("Default", true)
		FALootFrameTellsButton:SetTemplate("Default", true)
		FALootTellsFrameAwardButton:SetTemplate("Default", true)
		FALootTellsFrameActionButton:SetTemplate("Default", true)
		
		frame:SetScript("OnUpdate", nil)
	end
end)