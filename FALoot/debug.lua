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
    F.items.add(U.ItemLinkStrip("|cffa335ee|Hitem:127001::::::::110:266::13:5:689:1696:3408:600:670:::|h[Imbued Silkweave Cinch of the Fireflash]|h|r"));
	F.items.add(U.ItemLinkStrip("|cffa335ee|Hitem:139253::::::::110:266::6:3:1806:1507:3336:::|h[Fel-Bloated Venom Sac]|h|r"));
	F.items.add(U.ItemLinkStrip("|cffa335ee|Hitem:139251::::::::110:266::3:2:1807:1472:::|h[Despoiled Dragonscale]|h|r")); --139251:0:1807:1472
    F.items.add(U.ItemLinkStrip("|cffa335ee|Hitem:139189::::::::110:266::4:2:3379:1457:::|h[Hood of Darkened Visions]|h|r")); --LFR
    F.items.add(U.ItemLinkStrip("|cffa335ee|Hitem:139189::::::::110:266::3:2:1807:1472:::|h[Hood of Darkened Visions]|h|r")); --NORMAL
    F.items.add(U.ItemLinkStrip("|cffa335ee|Hitem:139189::::::::110:266::5:2:1805:1487:::|h[Hood of Darkened Visions]|h|r")); --HEROIC 139189:0:1805:1487
    F.items.add(U.ItemLinkStrip("|cffa335ee|Hitem:139189::::::::110:266::6:2:1806:1502:::|h[Hood of Darkened Visions]|h|r")); --MYTHIC
    F.items.add(U.ItemLinkStrip("|cffa335ee|Hitem:134426::::::::110:266::35:3:3416:1522:3336:::|h[Collar of Raking Claws]|h|r"));
    F.items.add(U.ItemLinkStrip("|cffa335ee|Hitem:133771:5436:::::::110:266::16:4:3418:40:1517:1813:::|h[Seacursed Wrap]|h|r"));

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