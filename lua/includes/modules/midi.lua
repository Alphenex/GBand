include("util/log.lua")
include("includes/modules/song.lua")

MidiFile = {}

function MidiFile:LoadMidiSong(path)
	if path == nil then return nil end

	local FILE = file.Open(path, "rb", "DATA")
	// TODO: Instead get the charts from Chorus Encore?

	// PARSE THE HEADER
	local midiType = FILE:Read(4)

	if (midiType != "MThd") then
		GBand:LogError("FAILED TO LOAD '" .. path .. "' | File is either not a MIDI or is corrupted.")
		return nil
	end

	FILE:Skip(4)
	local format = FILE:ReadBEUInt16()
	local trackCount = FILE:ReadBEUInt16()
	local timeDivision = FILE:ReadBEInt16()

	local _midi = {
		format = format or 0,
		trackCount = trackCount or 0,
		timeDivision = timeDivision or 0,
		timeLength = 0,
		tracks = {}
	}

	local maxTime = 0

	// PARSE MIDI TRACKS
	for i = 1, _midi.trackCount do
		print(i)
		local midiType = FILE:Read(4)

		if (midiType != "MTrk") then
			GBand:LogError("FAILED TO LOAD '" .. path .. "' | File is either not a MIDI or is corrupted.")
			return nil
		end

		local track = Track() // Create an almost empty track

		local trackLength = FILE:ReadBEUInt32()
		local trackEnd = FILE:Tell() + trackLength

		local time = 0
		local status = 0

		local latestNoteOn = {}

		while (FILE:Tell() < trackEnd) do
			time = time + FILE:ReadUVariedData()

			local peekByte = FILE:ReadByte()
			FILE:Skip(-1)
			
			if (bit.band(peekByte, 0x80) != 0) then
				status = peekByte
				FILE:Skip(1)
			end
			
			if (bit.band(status, 0xF0) != 0xF0) then 
				// This is a Channel Event
				local eventType = bit.band(status, 0xF0)
				local channel = bit.band(status, 0x0F) + 1

				local d1 = FILE:ReadByte()
				local d2 = 0
				if (bit.band(eventType, 0xE0) != EVENT_CHANNEL_PROGRAMCHANGE) then d2 = FILE:ReadByte() end
					
				if (eventType == EVENT_CHANNEL_NOTEON && d2 == 0) then eventType = EVENT_CHANNEL_NOTEOFF end // Note Ons with no velocity are Note Offs

				if (eventType == EVENT_CHANNEL_NOTEOFF) then
					local noteOn = latestNoteOn[d1]
					if (noteOn != nil) then
						local event = TrackEvent(EVENT_NOTE, nil, noteOn.time)
						event.note = d1
						event.duration = time - noteOn.time
						//event.channel = channel			!UNUSED!
						//event.velocity = noteOn.velocity	!UNUSED!

						if (track.events[noteOn.time] == nil) then track.events[noteOn.time] = {} end
						table.insert(track.events[noteOn.time], event)
						table.insert(track.categorizedEvents[EVENT_NOTE], event)

						latestNoteOn[d1] = nil
					end
				elseif (eventType == EVENT_CHANNEL_NOTEON) then
					latestNoteOn[d1] = { time = time, velocity = d2 }
				else
					local event = TrackEvent(EVENT_CHANNEL, eventType, noteOn.time)
					//event.channel = channel	!UNUSED!
					event.d1 = d1
					event.d2 = d2

					if (track.events[time] == nil) then track.events[time] = {} end
					table.insert(track.events[time], event)
					table.insert(track.categorizedEvents[EVENT_CHANNEL], event)
				end

			else 
				// This is a Meta or an Sysex Event (or something else which we will skip cuz WE DO NOT CARE)
				local metaType = FILE:ReadByte()
				
				if (status == 0xFF) then 
					if (metaType >= 0x01 && metaType <= 0x0F) then // Text Event
						local textLength = FILE:ReadUVariedData()
						local text = FILE:Read(textLength)

						if (text[1] == "[" && text[#text] == "]") then text = string.sub(text, 2, #text - 1) end // if the text starts and ends with brackets then remove the brackets

						if (metaType  == EVENT_TEXT_TRACKNAME) then track.name = text end 

						local event = TrackEvent(EVENT_TEXT, status, time)
						event.text = text

						if (track.events[time] == nil) then track.events[time] = {} end
						table.insert(track.events[time], event)
						table.insert(track.categorizedEvents[EVENT_TEXT], event)
					else
						local event = TrackEvent(EVENT_META, metaType, time)

						if (metaType == EVENT_META_TEMPO) then // TEMPO
							local mspqn = FILE:ReadBEUInt24()
							event.tempo = 60000000.0 / mspqn

							if (track.events[time] == nil) then track.events[time] = {} end
							table.insert(track.events[time], 1, event) // NOTE: Tempo events are always the first in timed event tables
							table.insert(track.categorizedEvents[EVENT_META], event)

						elseif (metaType == EVENT_META_TIMESIGNATURE) then // TIME SIGNATURE						
							FILE:Skip(1)
							event.numerator = FILE:ReadByte() 
							event.denominator = math.pow(FILE:ReadByte(), 2.0)
							FILE:Skip(2)

							if (track.events[time] == nil) then track.events[time] = {} end
							table.insert(track.events[time], event)
							table.insert(track.categorizedEvents[EVENT_META], event)

						elseif (metaType == EVENT_META_KEYSIGNATURE) then // KEY SIGNATURE
							FILE:Skip(1)
							event.numerator = FILE:ReadByte() 
							event.denominator = FILE:ReadByte()

							//if (track.events[time] == nil) then track.events[time] = {} end
							//table.insert(track.events[time], event)
							//table.insert(track.categorizedEvents[EVENT_META], event)
						else
							FILE:Skip(FILE:ReadUVariedData())
						end
					end
				elseif (status == 0xF0 || status == 0xF7) then
					FILE:Skip(FILE:ReadUVariedData()) // TODO: Process these!
				else 
					FILE:Skip(1) // No fucking clue, also skip
				end

			end
		end

		track.index = i
		maxTime = math.max(maxTime, time)

		_midi.tracks[i] = track
		if (_midi.name != nil) then _midi.tracks[_midi.name] = track end
	end

	_midi.timeLength = maxTime
	
	FILE:Close()
	
	return _midi 
end

// I hate myself
local _fileMeta = FindMetaTable("File")

function _fileMeta:ReadUVariedData()
	local res = self:ReadByte()
	if (bit.band(res, 0x80) == 0) then return res end

	res = bit.band(res, 0x7F)

	for i = 1, 3 do
		local val = self:ReadByte()
		res = bit.bor(bit.lshift(res, 7), bit.band(val, 0x7F))

		if (bit.band(val, 0x80) == 0) then break end
	end

	return res
end

function _fileMeta:ReadBEUInt32()
	return bit.bswap(self:ReadULong())
end

function _fileMeta:ReadBEInt32()
	return -(0xFF00 - bit.bxor(bit.bswap(self:ReadULong()), 0xFF00))
end

function _fileMeta:ReadBEUInt24()
	return bit.bswap(bit.lshift(bit.rshift(self:ReadULong(), 8), 8))
end

function _fileMeta:ReadBEInt24()
	return -(0xFF00 - bit.bxor(bit.bswap(bit.lshift(bit.rshift(self:ReadULong(), 8), 8)), 0xFF00))
end

function _fileMeta:ReadBEUInt16()
	return bit.bswap(bit.lshift(self:ReadUShort(), 16))
end

function _fileMeta:ReadBEInt16()
	return -(0xFF00 - bit.bxor(bit.bswap(bit.lshift(self:ReadUShort(), 16)), 0xFF00))
end
