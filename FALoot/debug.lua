local A = FALoot;
local E = A.events;
local F = A.functions;
local SD = A.sData;
local PD = A.pData;
local U = A.util;
local C = A.commands;
local UI = A.UI;

E.Register("PLAYER_LOGIN", function()

  if PD.debugOn > 0 then
    F.items.add(U.ItemLinkStrip("|cff0070dd|Hitem:141600::::::::100:259::9:3:3447:1815:1820:::|h[Wyrmtongue Spiteblade]|h|r"));
    F.items.add(U.ItemLinkStrip("|cff0070dd|Hitem:138450::::::::100:259:512:11:1:3387:100:::|h[Signet of Stormwind]|h|r"));
    
    E.Trigger("ITEM_UPDATE");
    
    UI.itemWindow.frame:Show();
  end
end)

C.Register("debug", function(level)
	if type(level) ~= "string" then
		return;
	end
	
	level = tonumber(level);
	
	if type(level) ~= "number" then
		return;
	end
	
	PD.debugOn = level;
	
	if PD.debugOn > 0 then
		U.debug("Debug is now ON ("..PD.debugOn..").");
	else
		U.debug("Debug is now OFF.");
	end
	
	E.Trigger("TELLSBUTTON_UPDATE");
end, "level -- sets the debug level.");