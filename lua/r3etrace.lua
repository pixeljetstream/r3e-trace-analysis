local ffi = require "ffi"
local r3e = require "r3e"
local r3emap = require "r3emap"
local r3emapfull = r3emap.init(true)
local r3emapbase = r3emap.init(false)

local R3E_TRACE_VERSION = 1

ffi.cdef ([[
typedef struct  {
  int version;
  int frameSize;
  int frames;
  int pollrate;
  int laps;
} r3e_trace_header;
]])

local _M = {}
  
function _M.createHeader(frames, pollrate, lapBegins, frameSize)
  local header = ffi.new("r3e_trace_header")
  header.version   = R3E_TRACE_VERSION
  header.frameSize = frameSize
  header.frames    = frames
  header.pollrate  = pollrate
  header.laps      = #lapBegins
  print("frameSize, frames, laps", header.frameSize, header.frames, header.laps)
  
  local str = ffi.string(header, ffi.sizeof("r3e_trace_header"))
  
  local laps  = ffi.new("int[?]", header.laps)
  for i=1,header.laps do
    laps[i-1] = lapBegins[i]
  end
  str = str..ffi.string(laps, ffi.sizeof("int") * header.laps)
  
  return str
end

local interpolatorBase  = r3emapbase.makeInterpolator()
local interpolatorFull  = r3emapfull.makeInterpolator()

function _M.loadTrace(filename, forcefulldata)
  -- read header
  print ("loading", filename)
  local file = io.open(filename, "rb")
  if (not file) then
    return 
  end
  
  local function readInto(out, sz)
    local bytes = file:read(sz)
    ffi.copy(out, bytes, sz)
  end
  
  local function readIntoStrided(out, instride, outstride, elements)
    if (instride == outstride) then
      readInto(out, instride * elements)
    else
      --local ptr = ffi.cast(out, "char*")
      for i=0,elements-1 do
        local bytes = file:read(instride)
        ffi.copy(out + i, bytes, instride)
      end
    end
    
  end
  
  local header = ffi.new("r3e_trace_header")
  readInto(header, ffi.sizeof("r3e_trace_header"))
  assert(header.version   == R3E_TRACE_VERSION, "wrong trace file version")
  assert(header.frameSize <= r3e.SHARED_SIZE or 
         header.frameSize == r3e.SHARED_SIZE_FULL, "wrong r3e data version")
  
  local fulldata     = forcefulldata or header.frameSize == r3e.SHARED_SIZE_FULL
  fulldata = fulldata and true or false
  local worksize     = fulldata and r3e.SHARED_SIZE_FULL      or r3e.SHARED_SIZE
  local workname     = fulldata and r3e.SHARED_TYPE_NAME_FULL or r3e.SHARED_TYPE_NAME
  local interpolator = fulldata and interpolatorFull          or interpolatorBase
  
  local laps     = header.laps
  local frames   = header.frames
  local pollrate = header.pollrate
  
  local lapsraw = ffi.new("int[?]", laps)
  readInto(lapsraw, ffi.sizeof("int") * laps)
  
  print("frameSize, frames, laps, pollrate, worksize, workname",header.frameSize, header.frames, header.laps, pollrate, worksize, workname)
  
  local contentTimes   = ffi.new("double[?]", frames)
  readInto(contentTimes, ffi.sizeof("double") * frames)
  
  local content   = ffi.new(workname.."[?]", frames)
  ffi.fill(content,  worksize * frames)
  readIntoStrided(content, header.frameSize, worksize, frames)
  
  local lapData = {}
  local posMin = {100000,100000,100000}
  local posMax = {-100000,-100000,-100000}
  
  local function checkPos(state)
    if (state.Player.Position.X ~= 0) then
      local pos = {state.Player.Position.X,state.Player.Position.Y,state.Player.Position.Z}
      for i=1,3 do 
        posMin[i] = math.min(posMin[i],pos[i])
        posMax[i] = math.max(posMax[i],pos[i])
      end
    end
  end
  
  do
    local lastTimeValid
    local lastTime 
    local lastLap
    local lastFrame
    local lapValid = true
    
    for i=0,frames-1 do
      local state     = content + i
      
      local timeValid = state.LapTimeCurrent >= 0
      if (state.CompletedLaps ~= lastLap)
      then
        if (lastTime) then
          local prev = content + (i-1)
          
          table.insert(lapData, { frameBegin = lastFrame, frameCount = i - lastFrame, timeBegin=lastTime, time=contentTimes[i-1] - lastTime, laptime = state.LapTimePrevious, valid = lastTimeValid} )
        end
        lastFrame = i
        lastTime  = contentTimes[i]
      end
      lastLap       = state.CompletedLaps
      lastTimeValid = timeValid
      
      checkPos(state)
    end
    local prev = content + (frames-1)
    table.insert(lapData, { frameBegin = lastFrame, frameCount = frames - lastFrame, timeBegin=lastTime, time=contentTimes[frames-1] - lastTime, laptime=prev.LapTimePrevious, valid = lastTimeValid} )
    laps = #lapData
  end
  
  local begin    = contentTimes[0]
  local duration = contentTimes[frames-1] - begin
  
  local trace = {
    fulldata = fulldata,
    header = header,
    filename = filename,
    begin  = begin,
    duration = duration,
    frames = frames,
    pollrate = pollrate,
    laps = laps,
    lapData = lapData,
    content = content,
    contentTimes = contentTimes,
    contentSize = contentSize,
    posMin = posMin,
    posMax = posMax,
  }
  
  function trace:getFrameIdx(time, startidx)
    -- FIXME should use binary search here
    local idx = math.max(math.min( math.floor( ((time-begin)*1000)/pollrate ), frames-2),0)
    
    local function check()
      return  contentTimes[idx] <= time and 
              contentTimes[idx+1] > time
    end
    
    local sign = (contentTimes[idx] > time) and -1 or 1
    while ( not check() and idx + sign >= 0 and idx + sign < frames-2) do
      idx = idx + sign
    end
    
    return idx
  end
  
  function trace:getFrame(state, time, startidx)
    local idx = trace:getFrameIdx(time, startidx)
    ffi.copy(state, content + idx, worksize)
    return idx
  end
  
  function trace:getFrameRaw(state, idx)
    local idx = math.max(math.min(idx, frames-1),0)
    ffi.copy(state, content + idx, worksize)
  end
  
  function trace:getInterpolatedFrame(state, time, startidx)
    local idx = trace:getFrameIdx(time, startidx)
    if (idx == frames-1) then
      ffi.copy(state, content + idx, worksize)
    else
      local stateA = content + idx
      local stateB = content + idx + 1
      local diff  = contentTimes[idx+1] - contentTimes[idx]
      local fracc = (time - contentTimes[idx])/diff
      interpolator(state, stateA, stateB, fracc)
    end
    return idx
  end
  
  function trace:assignContent(newcontent)
    -- copy
    ffi.copy(newcontent, content, contentSize)
    content = newcontent
    trace.content = newcontent
  end
  
  return trace
end

return _M
