local ffi          = require "ffi"
local r3e          = require "r3e"
local r3etrace     = require "r3etrace"
local utils        = require "utils"

----------------------------------
local config       = {record={}, replay={}, viewer={}}

utils.loadInto("config.lua", config)
utils.loadInto("config-user.lua", config)

local fulldata    = config.record.fulldata
local pollrate    = config.record.pollrate or 10
local onlydriving = config.record.onlydriving == nil or config.record.onlydriving
local saveonpause = config.record.saveonpause and onlydriving

local FRAMESIZE = fulldata and r3e.SHARED_SIZE_FULL      or r3e.SHARED_SIZE
local FRAMENAME = fulldata and r3e.SHARED_TYPE_NAME_FULL or r3e.SHARED_TYPE_NAME

local stateLast    = ffi.new( fulldata and r3e.SHARED_TYPE_FULL or r3e.SHARED_TYPE )
local state        = ffi.new( fulldata and r3e.SHARED_TYPE_FULL or r3e.SHARED_TYPE )

----------------------------------

local chunksMem = {}
local chunkFrames = 20 * 60 * math.floor(1000/pollrate) -- one chunk is 20 minutes
local chunkCount = 0
local framesMax = 0
local frames = 0
local diff = 0
local lapBegins = {}

local function allocateChunk()
  local mem = ffi.new(FRAMENAME.."[?]", chunkFrames)
  local memTime = ffi.new("double[?]", chunkFrames)
  chunksMem[chunkCount] = {mem,memTime}
  
  chunkCount = chunkCount + 1
  framesMax = chunkCount * chunkFrames
end
allocateChunk()


local lastLap
local lastTimeValid
local function record(state, stateLast, time)
  if (frames >= framesMax) then
    allocateChunk()
  end
  
  local c   = math.floor(frames/chunkFrames)
  local mem,memTime = chunksMem[c][1],chunksMem[c][2]
  
  local f   = frames - c*chunkFrames
  local dst = mem + f
  
  -- log lap begins
  local timeValid = state.LapTimeCurrent >= 0
  if ((state.CompletedLaps <= 0 and timeValid ~= lastTimeValid) or state.CompletedLaps ~= lastLap)
  then
    table.insert(lapBegins, frames)
    lastLap       = state.CompletedLaps
    lastTimeValid = timeValid
  end
  
  memTime[f] = time
  ffi.copy(dst, state, FRAMESIZE)
  
  if (frames > 0) then
    diff = diff + (state.Player.GameSimulationTime - stateLast.Player.GameSimulationTime)
  end
  
  frames = frames + 1
end


local function saveTrace(filename)
  print("saving", filename)
 
  local avgpollrate = math.max(1,math.floor(diff*1000/(frames-1)))
 
  local file = io.open(filename, "wb")
  local str = r3etrace.createHeader(frames, avgpollrate, lapBegins, FRAMESIZE)
  file:write(str)
  
  local numc = math.floor(frames/chunkFrames)
  local numf = frames - numc*chunkFrames
  print("numc, numf", numc, numf)
  
  -- first times
  -- then shared
  local sizes = {FRAMESIZE, ffi.sizeof("double")}
  for i=2,1,-1 do
    -- full chunks
    for c=0,numc-1 do
      local mem = chunksMem[c][i]
      str = ffi.string(mem, sizes[i] * chunkFrames)
      file:write(str)
    end
    
    -- frames
    local mem = chunksMem[numc][i]
    str = ffi.string(mem, sizes[i] * numf)
    file:write(str)
  end
  
  file:flush()
  file:close()
end

if (true) then 
  print "runtest.."
  local begin = os.clock()
  for i=0,9 do
    local time = os.clock()-begin
    state.Player.GameSimulationTime = time
    state.CompletedLaps = math.floor(i/2)
    
    record(state, stateLast, time)
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
  lapBegins = {}
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

local lastGameSimTime = nil
local lastSessionType = nil

local inSession = false
local inPause = false
local timeBegin

function update()
  if (not (r3e.isR3Erunning() and r3e.isMappable())) then 
    if (destroyMapping()) then
      return true
    end
    return
  end
  
  if (not mapping) then
    mapping = r3e.createMapping(false,fulldata)
    mapping:readData( stateLast )
  end
  
  -- update data
  mapping:readData( state )
  
  -- if need new session (restart keeps sessionType only resets gametime
  -- main menu is Session.Unavailable
  
  if (state.SessionType == r3e.Session.Unavailable or 
      state.SessionType ~= lastSessionType or
      state.Player.GameSimulationTime < lastGameSimTime) 
  then
    if (inSession) then
      endSession()
      inSession = false
    end
    if (state.SessionType == r3e.Session.Unavailable) then
      return
    end
  end
  
  if (not inSession) then
    beginSession(state)
    timeBegin = os.clock()
    inSession = true
    inPause   = true
  end
  
  
  if (inSession) then
    -- detect paused or not really driving ...
    -- if onlydriving is false we capture all events even if AI drives or game is paused...
    if (not onlydriving or 
      ( state.ControlType == r3e.Control.Player and
        state.Player.GameSimulationTime > 0 and       
        lastGameSimTime ~= state.Player.GameSimulationTime --paused
      ))
    then
      if (inPause) then print "recording..." end
      inPause = false
      local time = onlydriving and state.Player.GameSimulationTime or (os.clock()-timeBegin)
      record(state, stateLast, time)
    else
      if (not inPause) then 
        print "record paused" 
        if (saveonpause) then
          endSession()
          inSession = false
        end
      end
      inPause = true
    end
  end
  
  lastGameSimTime = state.Player.GameSimulationTime
  lastSessionType = state.SessionType
  
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

if (inSession) then
  endSession()
end
print "terminated"

