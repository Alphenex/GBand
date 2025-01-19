if (SERVER) then	

include("includes/modules/chart.lua")
include("includes/modules/midi.lua")

local function gband_loadchart(ply, cmd, args)
	ChartFile:LoadChartSong(args[1])
end
concommand.Add("gband_loadchart", gband_loadchart)

local function gband_loadmidi(ply, cmd, args)
	local midi = MidiFile:LoadMidiSong(args[1])
	
	PrintTable(midi)
end
concommand.Add("gband_loadmidi", gband_loadmidi)

else
	
end
