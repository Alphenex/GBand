if (SERVER) then	

include("includes/modules/midi.lua")

local function gband_loadchart(ply, cmd, args)
	local skeebeedee = MidiFile(args[1])
end
concommand.Add("gband_loadchart", gband_loadchart)


else
	
end
