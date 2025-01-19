// ------------------- //
// ------ EVENT ------ //
// ------------------- //

EVENT_CHANNEL = 1
EVENT_NOTE = 2 // Normally Midi Channel Note on or Note off events however we seperated them because it is easier to process them
EVENT_META = 3
EVENT_TEXT = 4

// These values are for MIDI stuff but CHART files don't need specific binary checks so it is fine
EVENT_CHANNEL_NOTEOFF = 0x80 // This and the one below won't be used, only for easy check
EVENT_CHANNEL_NOTEON = 0x90
EVENT_CHANNEL_KEYAFTERTOUCH = 0xA0
EVENT_CHANNEL_CONTROLCHANGE = 0xB0
EVENT_CHANNEL_PROGRAMCHANGE = 0xC0
EVENT_CHANNEL_CHANNELAFTERTOUCH = 0xD0
EVENT_CHANNEL_PITCHBENDCHANGE = 0xE0

EVENT_CHANNEL_BANKSELECT = 0x00
EVENT_CHANNEL_MODULATION = 0x01
EVENT_CHANNEL_VOLUME = 0x07
EVENT_CHANNEL_BALANCE = 0x08
EVENT_CHANNEL_PAN = 0x0A
EVENT_CHANNEL_SUSTAIN = 0x40

EVENT_META_TEMPO = 0x51
EVENT_META_TIMESIGNATURE = 0x58
EVENT_META_KEYSIGNATURE = 0x59

EVENT_TEXT_TEXT = 0x01
EVENT_TEXT_COPYRIGHT = 0x02
EVENT_TEXT_TRACKNAME = 0x03
EVENT_TEXT_INSTRUMENTNAME = 0x04
EVENT_TEXT_LYRICS = 0x05
EVENT_TEXT_MARKER = 0x06
EVENT_TEXT_CUEPOINT = 0x07

TrackEvent = {}
TrackEvent.__index = TrackEvent

function TrackEvent:new(event_type, event_sub_type, time)
	local _TrackEvent = {
		eventType = event_type or nil,
		eventSubType = event_sub_type or nil, 
		time = time or 0
	}

	setmetatable(_TrackEvent, TrackEvent)
	return _TrackEvent 
end

setmetatable( TrackEvent, {__call = TrackEvent.new } )

// ------------------- //
// ------ TRACK ------ //
// ------------------- //

Track = {}
Track.__index = Track

function Track:new(name, index)
	local _Track = {
		name = name or nil,
		index = index or 1,

		events = {}, // Stored by the time when they are run, basically if it is run at 500th tick then it is stored at events[500]
		categorizedEvents = {}
	}

	_Track.categorizedEvents[EVENT_CHANNEL] = {}
	_Track.categorizedEvents[EVENT_NOTE] = {}
	_Track.categorizedEvents[EVENT_META] = {}
	_Track.categorizedEvents[EVENT_TEXT] = {}

	setmetatable(_Track, Track)
	return _Track 
end

setmetatable( Track, {__call = Track.new } )
