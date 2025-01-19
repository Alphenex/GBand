include("util/log.lua")
include("includes/modules/song.lua")

ChartFile = {}

local CHART_TOKEN_SECTION = 1
local CHART_TOKEN_LBRACKET = 2
local CHART_TOKEN_RBRACKET = 3
local CHART_TOKEN_KEY = 4
local CHART_TOKEN_VALUE = 5

local function ExplodeString(line)
	local strTable = {}
	local strTable2 = {}

	for s in string.gmatch(line, "[^%s]+") do
		table.insert(strTable, s)
	end

	// HACK: We artifically add the whitespace... fix this shit
	local quoted = false
	local quote = nil
	for i = 1, #strTable do
		local str = strTable[i]
		if (quoted == false && str[1] == "\"" && str[#str] != "\"") then
			quote = strTable[i]
			quoted = true
		elseif (quoted == true && str[#str] == "\"") then
			quote = quote .. " " .. str
			table.insert(strTable2, quote)

			quote = nil
			quoted = false
		elseif ( quoted == true ) then
			quote = quote .. " " .. str
		else
			table.insert(strTable2, str)
		end
	end

	return strTable2
end

local function TokenizeChartFile(path, FILE)
	local dataTree = {}
	local line = 0
	local inBrackets = false
	local inSectionName = nil
	local inKeyName = nil

	while (FILE:Tell() < FILE:Size()) do
		local strTable = ExplodeString(FILE:ReadLine())
		local lineHasKey = false

		for k, v in ipairs(strTable) do
			if (v == "=") then continue end

			if (v == "{") then
				inBrackets = true

			elseif (v == "}") then
				inBrackets = false
				inKeyName = nil

			elseif (inBrackets == false) then
				local name = string.sub(v, 2, #v - 1)
				if (dataTree[name] == nil) then dataTree[name] = {} end
				inSectionName = name

			elseif (inBrackets == true) then

				if (lineHasKey == true) then
					// Kill me
					local name = v
					if (v[1] == "\"" && v[#v] == "\"") then name = string.sub(v, 2, #v - 1) end
					
					local num = tonumber(name)
					if (num != nil) then
						name = num
					end

					table.insert(dataTree[inSectionName][inKeyName][#dataTree[inSectionName][inKeyName]], name)
				elseif (lineHasKey == false) then
					local name = v
					local num = tonumber(name)
					if (num != nil) then
						name = num
					end
					
					if (dataTree[inSectionName][name] == nil) then dataTree[inSectionName][name] = {} end
					
					table.insert(dataTree[inSectionName][name], {})

					lineHasKey = true					
					inKeyName = name
				end

			else
				GBand:LogError("Chart File '" .. path .. "' errored at line: " .. line .. " at word " .. v)
			end
		end
		
		line = line + 1
	end

	return dataTree
end

local function GetValueFromSectionKey(section, key, val, subval)
	local keyvalues = section[key]
	if (keyvalues == nil) then 
		return nil 
	end

	return keyvalues[val or 1][subval or 1]
end

local function GetValuesFromSectionKey(section, key)
	return section[key]
end

function ChartFile:LoadChartSong(path)
	if path == nil then return nil end

	local FILE = file.Open(path, "rb", "DATA")

	if (FILE == nil) then
		GBand:LogError("\"" .. path .. "\" Failed to load Chart.")
		return
	end 

	local chartTree = TokenizeChartFile(path, FILE)

	local songKeyvalues = chartTree["Song"]
	if (songKeyvalues == nil) then
		GBand:LogError("\"" .. path .. "\" 'Song' Section does not exist in chart.")
		return
	end

	// These are mostly useless however they are basically the backup plan if song.ini doesn't have em

	local globTrack = Track("Global", 1)

	local songResolution = GetValueFromSectionKey(songKeyvalues, "Resolution")
	
	if (songResolution == nil || songResolution == 0) then
		GBand:LogError("\"" .. path .. "\" Song 'Resolution' does not exist in chart or is zero.")
		return
	end

	local songName = GetValueFromSectionKey(songKeyvalues, "Name")
	local songArtist = GetValueFromSectionKey(songKeyvalues, "Artist")
	local songCharter = GetValueFromSectionKey(songKeyvalues, "Charter")
	local songAlbum = GetValueFromSectionKey(songKeyvalues, "Album")
	local songGenre = GetValueFromSectionKey(songKeyvalues, "Genre")
	local songYear = GetValueFromSectionKey(songKeyvalues, "Year")
	local songDifficulty = GetValueFromSectionKey(songKeyvalues, "Difficulty")
	local songOffset = GetValueFromSectionKey(songKeyvalues, "Offset")
	local songPreviewStart = GetValueFromSectionKey(songKeyvalues, "PreviewStart")
	local songPreviewEnd = GetValueFromSectionKey(songKeyvalues, "PreviewEnd")
	local songMusicStream = GetValueFromSectionKey(songKeyvalues, "MusicStream")
	local songPlayer2 = GetValueFromSectionKey(songKeyvalues, "Player2")

	print(songName)

	local strackKeyValues = chartTree["SyncTrack"]
	if (strackKeyValues == nil) then
		GBand:LogError("SyncTrack section does not exist in chart " .. path)
		return
	end

	for time, values in pairs(strackKeyValues) do
		for _, v in ipairs(values) do
			local event = nil
			local c = v[1]
			if (c == "B") then
				event = TrackEvent(EVENT_META, EVENT_META_TEMPO, time)
				event.tempo = v[2]
		
				if (globTrack.events[time] == nil) then globTrack.events[time] = {} end
				table.insert(globTrack.events[time], 1, event) // NOTE: Tempo events are always the first in timed event tables
				table.insert(globTrack.categorizedEvents[EVENT_META], event)
			elseif (c == "TS") then
				event = TrackEvent(EVENT_META, EVENT_META_TIMESIGNATURE, time)
				event.numerator = v[2] 
				event.denominator = math.pow(v[3] or 2, 2.0)
		
				if (globTrack.events[time] == nil) then globTrack.events[time] = {} end
				table.insert(globTrack.events[time], event)
				table.insert(globTrack.categorizedEvents[EVENT_META], event)
			end
		end
	end

	local eventsKeyValues = chartTree["Events"]
	if (eventsKeyValues != nil) then // If Events section exists then try to add track events
		for time, values in pairs(eventsKeyValues) do
			for _, v in ipairs(values) do
				local event = nil
				if (v[1] != "E") then return end

				local event = TrackEvent(EVENT_TEXT, EVENT_TEXT_TEXT, time)				
				local text = v[2]
				if (text[1] == "\"" && text[#text] == "\"") then text = string.sub(text, 2, #text - 1) end

				if (string.sub(text, 1, 5) == "lyric") then
					text = string.sub(text, 7, #text)
					event.eventSubType = EVENT_TEXT_LYRICS
				elseif (string.sub(text, 1, 7) == "section") then
					text = string.sub(text, 9, #text)
				elseif (string.sub(text, 1, 3) == "prc") then
					text = string.sub(text, 5, #text)
				end
				
				event.text = text

				if (globTrack.events[time] == nil) then globTrack.events[time] = {} end
				table.insert(globTrack.events[time], event)
				table.insert(globTrack.categorizedEvents[EVENT_TEXT], event)
			end
		end
	end

	local instruments = {
		"Single",
		"DoubleGuitar",
		"DoubleBass",
		"DoubleRhythm",
		"Drums",
		"Keyboard"
	}

	local difficulties = {
		"Easy",
		"Medium",
		"Hard",
		"Expert"
	}

	local _chart = {
		trackCount = trackCount or 0,
		timeDivision = timeDivision or 0,
		timeLength = 0,
		tracks = {}
	}

	_chart.tracks[1] = globTrack
	_chart.tracks["Global"] = globTrack

	for _, instrument in ipairs(instruments) do
		local noteAccum = {}
		for _, difficulty in ipairs(difficulties) do
			local name = difficulty .. instrument
			local notes = chartTree[name]
			if (notes == nil) then continue end
			
			local track = Track(name, #_chart.tracks + 1, 0)

			for time, accNote in pairs(noteAccum) do
				if (track.events[time] == nil) then track.events[time] = {} end
				table.insert(track.events[time], accNote[1])
				table.insert(track.categorizedEvents[EVENT_NOTE], accNote[1])
			end

			for time, values in pairs(notes) do
				for _, v in ipairs(values) do
					local event = nil
					if (v[1] == "N") then
						event = TrackEvent(EVENT_NOTE, nil, time)
						event.note = v[2]
						if (event.note > 7) then
							GBand:LogError("Unknown Note? " .. event.note)
							continue 
						end
						event.duration = v[3]
						//event.channel = 1		!UNUSED!
						//event.velocity = 0 	!UNUSED!
				
						if (track.events[time] == nil) then track.events[time] = {} end
						if (noteAccum[time] == nil) then noteAccum[time] = {} end

						table.insert(noteAccum[time], event)
						table.insert(track.events[time], event)

						table.insert(track.categorizedEvents[EVENT_NOTE], event)
					elseif (v[1] == "E") then
						event = TrackEvent(EVENT_TEXT, EVENT_TEXT_TEXT, time)	
						event.text = v[2]

						if (track.events[time] == nil) then track.events[time] = {} end
						table.insert(track.events[time], event)
						table.insert(track.categorizedEvents[EVENT_TEXT], event)
					elseif (v[1] == "S") then
						// TODO: These are basically big points of star power, eventually add them
					end
				end
			end

			_chart.tracks[track.index] = track
			_chart.tracks[name] = track	
		end
	end

	print("\n\n[GLOBAL]\n\n")
	PrintTable(_chart.tracks["Global"])
	print("\n\n[EXPERTSINGLE]\n\n")
	PrintTable(_chart.tracks["ExpertSingle"])
	print("\n\n[HARDSINGLE]\n\n")
	PrintTable(_chart.tracks["HardSingle"])
	print("\n\n[MEDIUMSINGLE]\n\n")
	PrintTable(_chart.tracks["MediumSingle"])
	print("\n\n[EASYSINGLE]\n\n")
	PrintTable(_chart.tracks["EasySingle"])

	FILE:Close()
	
	return _midi 
end
