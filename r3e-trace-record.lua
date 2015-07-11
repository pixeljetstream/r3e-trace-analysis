local ffi          = require "ffi"
local r3e          = require "r3e"
local r3etrace     = require "r3etrace"
local utils        = require "utils"
local stateLast    = ffi.new( r3e.SHARED_TYPE )
local state        = ffi.new( r3e.SHARED_TYPE )

local config = {}

utils.loadInto("config.lua", config)
utils.loadInto("config-user.lua", config)

local pollrate = config.pollrate or 10

----------------------------------

local chunksMem = {}
local chunkFrames = 20 * 60 * math.floor(1000/config.pollrate) -- one chunk is 20 minutes
local chunkCount = 0
local framesMax = 0
local frames = 0
local diff = 0
local lapBegins = {0}

local function allocateChunk()
  local mem = ffi.new(r3e.SHARED_TYPE_NAME.."[?]", chunkFrames)
  chunksMem[chunkCount] = mem
  
  chunkCount = chunkCount + 1
  framesMax = chunkCount * chunkFrames
end
allocateChunk()


local lastLap
local function record(state, stateLast)
  if (frames >= framesMax) then
    allocateChunk()
  end
  
  local c   = math.floor(frames/chunkFrames)
  local mem = chunksMem[c]
  
  local f   = frames - c*chunkFrames
  local dst = mem + f
  
  -- log lap begins
  if (state.LapTimeCurrent >= 0 and state.CompletedLaps >= 0 and lastLap ~= state.CompletedLaps)
  then
    table.insert(lapBegins, frames)
    lastLap = state.CompletedLaps
  end
  
  ffi.copy(dst, state, r3e.SHARED_SIZE)
  
  if (frames > 0) then
    diff = diff + (state.Player.GameSimulationTime - stateLast.Player.GameSimulationTime)
  end
  
  frames = frames + 1
end


local function saveTrace(filename)
  print("saving", filename)
 
  local avgpollrate = math.max(1,math.floor(diff*1000/(frames-1)))
 
  local file = io.open(filename, "wb")
  local str = r3etrace.createHeader(frames, avgpollrate, lapBegins)
  file:write(str)
  
  local numc = math.floor(frames/chunkFrames)
  local numf = frames - numc*chunkFrames
  print("numc, numf", numc, numf)
  
  -- full chunks
  for c=0,numc-1 do
    local mem = chunksMem[c]
    str = ffi.string(mem, r3e.SHARED_SIZE * chunkFrames)
    file:write(str)
  end
  
  -- frames
  local mem = chunksMem[numc]
  str = ffi.string(mem, r3e.SHARED_SIZE * numf)
  file:write(str)
  
  file:flush()
  file:close()
  
end

if (true) then 
  print "runtest.."
  local begin = os.clock()
  for i=0,9 do
    state.Player.GameSimulationTime = os.clock()-begin
    state.CompletedLaps = math.floor(i/2)
    
    record(state, stateLast)
    state,stateLast = stateLast, state
    
    utils.sleep( math.max(1,math.floor(pollrate)) )
  end
  saveTrace("trace_test.r3t")

  local test = r3etrace.loadTrace("trace_test.r3t")
  print(test.frames)
  
  test:getInterpolatedFrame( state, 0.045)
  print(state.Player.GameSimulationTime)
  
  print "runtest completed"
end

local mapping = nil
local function destroyMapping()
  if (mapping) then
    mapping:destroy()
    mapping = nil
    return true
  end
end


local traceFileName
local function beginSession(state)
  frames = 0
  lapBegins = {0}
  diff = 0
  lastLap = nil
  traceFileName = "trace_"..os.date("%y%m%d_%H%M%S")..".r3t"
  print("session begin",traceFileName)
end

local function endSession()
  print("session end")
  saveTrace(traceFileName)
  traceFileName = nil
  frames = 0
end

local delay = 2
local lastGameSimTime = 0
local inSession = false

function update()
  if (not (r3e.isR3Erunning() and r3e.isMappable())) then 
    if (destroyMapping()) then
      return true
    end
    return
  end
  
  if (not mapping) then
    mapping = r3e.createMapping()
    mapping:readData( stateLast )
  end
  
  -- update data
  mapping:readData( state )
  
  -- no session?
  -- FIXME detect if paused
  if (state.SessionType == r3e.Session.Unavailable) then
    if (inSession) then
      endSession()
      inSession = false
    end
    inSession = false
    return
  end
  
  if (not inSession) then
    beginSession(state)
    inSession = true
  end
  
  -- detect paused...
  if (inSession) then
    if (state.ControlType ~= r3e.Control.Unavailable) 
    then
      record(state, stateLast)
    else
      --print "skipping"
    end
  end
  
  -- swap
  state,stateLast = stateLast,state
end

print "waiting..."
while true do
  if (update()) then
    break
  end
  
  utils.sleep( math.max(1,math.floor(pollrate)) )
end
print "terminated"
