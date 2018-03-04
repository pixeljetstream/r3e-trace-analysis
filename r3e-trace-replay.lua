local ffi          = require "ffi"
local r3e          = require "r3e"
local r3etrace     = require "r3etrace"
local utils        = require "utils"
local r3emap       = require "r3emap"
r3emap = r3map.init(true)

----------------------------------
local state        = ffi.new( r3e.SHARED_TYPE_FULL )

local config       = {record={}, replay={}, viewer={}}

utils.loadInto("config.lua", config)
utils.loadInto("config-user.lua", config)

local args = _ARGS or {...}

local traceFileName = args[2] or "trace_150712_170141.r3t"

local trace = r3etrace.loadTrace(traceFileName)

assert(trace.header.frameSize == r3e.SHARED_SIZE_FULL, "replay only supports fulldata recordings")

local timebased    = config.replay.timebased 
local dumpframes   = config.replay.dumpframes or 120
local dumpinterval = config.replay.dumpinterval or 2

local playspeed    = config.replay.playspeed or 1
local playrate     = config.replay.playrate or math.max(1,math.floor(trace.pollrate/2))

----------------------------------


do
  -- get properties
  local allprops = r3emap.getAllProperties(false)
  local lkprops = {}
  for i,v in ipairs(allprops) do
    lkprops[v.name] = i
  end
  -- find 
  local used = {}
  if (config.replay.dumpfilter) then
    for i,v in ipairs(config.replay.dumpfilter) do
      local idx = lkprops[v] 
      if (idx) then
        table.insert(used, allprops[idx])
      end
    end
  else
    used = allprops
  end
  
  if (#used > 0) then
    local fnaccess = r3emap.makeAccessor(used)
    local results = {}
    
    fnPrint = function(state)
      fnaccess(results, state)
      r3emap.printResults(used, results)
    end
    
  else
    -- dummy func
    fnPrint = function(state) end
  end
end

----------------------------------

-- write only mapping
local mapping = r3e.createMapping(true, true)

print("replaying",traceFileName)

if (timebased) then
  -- time based
  local begin    = trace.begin - os.clock()
  local time     = 0
  local timeEnd  = trace.begin + trace.duration

  local function update()
    time = os.clock() * playspeed + begin
    trace:getInterpolatedFrame( state, time )
    mapping:writeData( state )
  end

  local lastInterval = nil
  while (time <= timeEnd) do
    update()
    
    -- dump every once and a while
    local interval = math.floor(time/dumpinterval)
    if (interval ~= lastInterval) then
      print("PLAYER TIME",time)
      fnPrint(state)
      print ""
      lastInterval = interval
    end
    
    utils.sleep( playrate )
  end
else
  --frame based
  local frame = 0
  local frameEnd = trace.frames
  
  local lastInterval = nil
  while (frame < frameEnd) do
    trace:getFrameRaw( state, frame )
    mapping:writeData( state )
    
    -- dump every once and a while
    local interval = math.floor(frame/dumpframes)
    if (interval ~= lastInterval or true) then
      print("PLAYER FRAME", frame)
      fnPrint(state)
      print ""
      lastInterval = interval
    end
    
    frame = frame + playspeed
    
    utils.sleep( playrate )
  end
end
print("completed")

mapping:destroy()