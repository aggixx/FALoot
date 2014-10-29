local A = FALoot;
local E = A.events;
local F = A.functions;
local SD = A.sData;
local PD = A.pData;
local U = A.util;
local C = A.commands;

E.Register("PLAYER_LOGIN", function()

  if PD.debugOn > 0 then
    F.items.add("96379:0")
    F.items.add("96740:0")
    F.items.add("96740:0")
    F.items.add("96373:0")
    F.items.add(U.ItemLinkStrip("|cffa335ee|Hitem:94775:4875:4609:0:0:0:65197:904070771:89:166:465|h[Beady-Eye Bracers]|h|r"))
    F.items.add(U.ItemLinkStrip("|cffa335ee|Hitem:98177:0:0:0:0:0:-356:1744046834:90:0:465|h[Tidesplitter Britches of the Windstorm]|h|r"))
    F.items.add("96384:0")
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