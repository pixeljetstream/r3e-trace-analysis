local ffi          = require "ffi"
local r3e          = require "r3e"
local r3etrace     = require "r3etrace"
local utils        = require "utils"
local state        = ffi.new( r3e.SHARED_TYPE )

local args = _ARGS or {...}

local traceFileName = args[2] or "trace_test.r3t"

local trace = r3etrace.loadTrace(traceFileName)

local playbackrate = math.max(1,math.floor(trace.pollrate/2))

-- write only mapping
local mapping = r3e.createMapping(true)

local begin    = trace.begin - os.clock()
local time     = 0
local timeEnd  = trace.begin + trace.duration


local function update()
  time = os.clock() + begin
  local idx = trace:getInterpolatedFrame( state, time )
  mapping:writeData( state )
  --print(time, state.Player.GameSimulationTime, idx)
end

-- sleep resolution may not be so great
print("replaying",traceFileName)
while (time <= timeEnd) do
  update()
  utils.sleep( playbackrate )
end
print("completed")

mapping:destroy()