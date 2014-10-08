local frame = CreateFrame("Frame");

frame:SetScript("OnEvent", function(self, event, ...)
  local A = FALoot;
  local F = A.functions
  local SD = A.sData;
  local PD = A.pData;
  local U = A.util;

  if PD.debugOn > 0 then
    F.items.add("96379:0")
    F.items.add("96740:0")
    F.items.add("96740:0")
    F.items.add("96373:0")
    F.items.add(U.ItemLinkStrip("|cffa335ee|Hitem:94775:4875:4609:0:0:0:65197:904070771:89:166:465|h[Beady-Eye Bracers]|h|r"))
    F.items.add(U.ItemLinkStrip("|cffa335ee|Hitem:98177:0:0:0:0:0:-356:1744046834:90:0:465|h[Tidesplitter Britches of the Windstorm]|h|r"))
    F.items.add("96384:0")
  end
  
  self:UnregisterEvent("PLAYER_ENTERING_WORLD");
end)

frame:RegisterEvent("PLAYER_ENTERING_WORLD");