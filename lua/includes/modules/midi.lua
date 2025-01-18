include("util/log.lua")

// ------------------------ //
// ------ MIDI EVENT ------ //
// ------------------------ //

MIDI_CHANNEL = 0
MIDI_NOTE = 1 // Normally Midi Channel Note on or Note off events however we seperated them because it is easier to process them
MIDI_META = 2
MIDI_TEXT = 3

MIDI_CHANNEL_NOTEOFF = 0x80 // This and the one below won't be used, only for easy check
MIDI_CHANNEL_NOTEON = 0x90
MIDI_CHANNEL_KEYAFTERTOUCH = 0xA0
MIDI_CHANNEL_CONTROLCHANGE = 0xB0
MIDI_CHANNEL_PROGRAMCHANGE = 0xC0
MIDI_CHANNEL_CHANNELAFTERTOUCH = 0xD0
MIDI_CHANNEL_PITCHBENDCHANGE = 0xE0

MIDI_CHANNEL_BANKSELECT = 0x00
MIDI_CHANNEL_MODULATION = 0x01
MIDI_CHANNEL_VOLUME = 0x07
MIDI_CHANNEL_BALANCE = 0x08
MIDI_CHANNEL_PAN = 0x0A
MIDI_CHANNEL_SUSTAIN = 0x40

MIDI_META_TEMPO = 0x51
MIDI_META_TIMESIGNATURE = 0x58
MIDI_META_KEYSIGNATURE = 0x59

MIDI_TEXT_TEXT = 0x01
MIDI_TEXT_COPYRIGHT = 0x02
MIDI_TEXT_TRACKNAME = 0x03
MIDI_TEXT_INSTRUMENTNAME = 0x04
MIDI_TEXT_LYRICS = 0x05
MIDI_TEXT_MARKER = 0x06
MIDI_TEXT_CUEPOINT = 0x07

MidiEvent = {}
MidiEvent.__index = MidiEvent

function MidiEvent:new(event_type, event_sub_type, time)
	local _MidiEvent = {
		eventType = event_type or nil,
		eventSubType = event_sub_type or nil, 
		time = time or 0
	}

	setmetatable(_MidiEvent, MidiEvent)
	return _MidiEvent 
end

setmetatable( MidiEvent, {__call = MidiEvent.new } )

// ------------------------ //
// ------ MIDI TRACK ------ //
// ------------------------ //

MidiTrack = {}
MidiTrack.__index = MidiTrack

function MidiTrack:new(name, index, time_length)
	local _MidiTrack = {
		name = name or nil,
		index = index or 0,
		timeLength = time_length or 0,

		events = {}, // Stored by the time when they are run, basically if it is run at 500th tick then it is stored at events[500]
		categorizedEvents = {}
	}

	_MidiTrack.categorizedEvents[MIDI_CHANNEL] = {}
	_MidiTrack.categorizedEvents[MIDI_NOTE] = {}
	_MidiTrack.categorizedEvents[MIDI_META] = {}
	_MidiTrack.categorizedEvents[MIDI_TEXT] = {}

	setmetatable(_MidiTrack, MidiTrack)
	return _MidiTrack 
end

setmetatable( MidiTrack, {__call = MidiTrack.new } )

// ----------------------- //
// ------ MIDI FILE ------ //
// ----------------------- //

MidiFile = {}
MidiFile.__index = MidiFile

function MidiFile:new(path)
	if path == nil then return end

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
		tracks = {}
	}

	// PARSE MIDI TRACKS
	for i = 1, _midi.trackCount do
		print(i)
		local midiType = FILE:Read(4)

		if (midiType != "MTrk") then
			GBand:LogError("FAILED TO LOAD '" .. path .. "' | File is either not a MIDI or is corrupted.")
			return nil
		end

		local track = MidiTrack() // Create an almost empty track

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
				if (bit.band(eventType, 0xE0) != MIDI_CHANNEL_PROGRAMCHANGE) then d2 = FILE:ReadByte() end
					
				if (eventType == MIDI_CHANNEL_NOTEON && d2 == 0) then eventType = MIDI_CHANNEL_NOTEOFF end // Note Ons with no velocity are Note Offs

				if (eventType == MIDI_CHANNEL_NOTEOFF) then
					local noteOn = latestNoteOn[d1]
					if (noteOn != nil) then
						local event = MidiEvent(MIDI_NOTE, nil, noteOn.time)
						event.channel = channel
						event.note = d1
						event.velocity = noteOn.velocity
						event.duration = time - noteOn.time

						if (track.events[noteOn.time] == nil) then track.events[noteOn.time] = {} end
						table.insert(track.events[noteOn.time], event)
						table.insert(track.categorizedEvents[MIDI_NOTE], event)

						latestNoteOn[d1] = nil
					end
				elseif (eventType == MIDI_CHANNEL_NOTEON) then
					latestNoteOn[d1] = { time = time, velocity = d2 }
				else
					local event = MidiEvent(MIDI_CHANNEL, eventType, noteOn.time)
					event.channel = channel
					event.d1 = d1
					event.d2 = d2

					if (track.events[time] == nil) then track.events[time] = {} end
					table.insert(track.events[time], event)
					table.insert(track.categorizedEvents[MIDI_CHANNEL], event)
				end

			else 
				// This is a Meta or an Sysex Event (or something else which we will skip cuz WE DO NOT CARE)
				local metaType = FILE:ReadByte()
				
				if (status == 0xFF) then 
					if (metaType >= 0x01 && metaType <= 0x0F) then // Text Event
						local textLength = FILE:ReadUVariedData()
						local text = FILE:Read(textLength)

						if (metaType  == MIDI_TEXT_TRACKNAME) then track.name = text end 

						local event = MidiEvent(MIDI_TEXT, status, time)
						event.text = text

						if (track.events[time] == nil) then track.events[time] = {} end
						table.insert(track.events[time], event)
						table.insert(track.categorizedEvents[MIDI_TEXT], event)
					else
						local event = MidiEvent(MIDI_META, metaType, time)

						if (metaType == MIDI_META_TEMPO) then // TEMPO
							local mspqn = FILE:ReadBEUInt24()
							event.tempo = math.floor(60000000.0 / mspqn)

							if (track.events[time] == nil) then track.events[time] = {} end
							table.insert(track.events[time], 1, event) // NOTE: Tempo events are always the first in timed event tables
							table.insert(track.categorizedEvents[MIDI_META], event)

						elseif (metaType == MIDI_META_TIMESIGNATURE) then // TIME SIGNATURE						
							FILE:Skip(1)
							event.numerator = FILE:ReadByte() 
							event.denominator = math.pow(FILE:ReadByte(), 2.0)
							FILE:Skip(2)

							if (track.events[time] == nil) then track.events[time] = {} end
							table.insert(track.events[time], event)
							table.insert(track.categorizedEvents[MIDI_META], event)

						elseif (metaType == MIDI_META_KEYSIGNATURE) then // KEY SIGNATURE
							FILE:Skip(1)
							event.numerator = FILE:ReadByte() 
							event.denominator = FILE:ReadByte()

							if (track.events[time] == nil) then track.events[time] = {} end
							table.insert(track.events[time], event)
							table.insert(track.categorizedEvents[MIDI_META], event)
						else
							FILE:Skip(FILE:ReadUVariedData())
						end
					end
				elseif (status == 0xF0 || status == 0xF7) then
					FILE:Skip(FILE:ReadUVariedData()) // Sysex Event, just skip
				else 
					FILE:Skip(1) // No fucking clue, also skip
				end

			end
		end

		track.index = i
		track.timeLength = time

		_midi.tracks[i] = track
		if (_midi.name != nil) then _midi.tracks[_midi.name] = track end
	end

	FILE:Close()
	
	setmetatable(_midi, MidiFile)
	return _midi 
end

setmetatable( MidiFile, {__call = MidiFile.new } )

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
