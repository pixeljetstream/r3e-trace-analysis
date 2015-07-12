local ffi = require "ffi"
local r3e = require "r3e"
local r3emap = require "r3emap"

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
  
function _M.createHeader(frames, pollrate, lapBegins)
  local header = ffi.new("r3e_trace_header")
  header.version   = R3E_TRACE_VERSION
  header.frameSize = r3e.SHARED_SIZE
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

local interpolator
do
  local function lerp(a, b, t) return a * (1-t) + b * t  end
  
  -- create interpolator
  interpolator = function(stateOut, stateA, stateB, fracc)
    ffi.copy(stateOut, stateA, r3e.SHARED_SIZE)

    -- interpolate at least time
    stateOut.Player.GameSimulationTime = lerp( stateA.Player.GameSimulationTime, stateB.Player.GameSimulationTime, fracc)
  end
  
  -- use full interpolator
  interpolator = r3emap.makeInterpolator()
end


function _M.loadTrace(filename)
  -- read header
  print ("loading", filename)
  local file = io.open(filename, "rb")
  assert(file,filename)
  
  local function readInto(out, sz)
    local bytes = file:read(sz)
    ffi.copy(out, bytes, sz)
  end
  
  local header = ffi.new("r3e_trace_header")
  readInto(header, ffi.sizeof("r3e_trace_header"))
  assert(header.version   == header.version, "wrong trace file version")
  assert(header.frameSize == r3e.SHARED_SIZE, "wrong r3e data version")
  
  local laps     = header.laps
  local frames   = header.frames
  local pollrate = header.pollrate
  
  local lapsraw = ffi.new("int[?]", laps)
  readInto(lapsraw, ffi.sizeof("int") * laps)
  
  print("frameSize, frames, laps, pollrate",header.frameSize, header.frames, header.laps, pollrate)
  
  local contentTimes   = ffi.new("double[?]", frames)
  readInto(contentTimes, ffi.sizeof("double") * frames)
  
  local content   = ffi.new(r3e.SHARED_TYPE_NAME.."[?]", frames)
  readInto(content, r3e.SHARED_SIZE * frames)
  
  local lapData = {}
  for i=0,header.laps-1 do
    local lastlap = (i == (header.laps-1))
    
    local frameBegin = lapsraw[i]
    local frameEnd   = lastlap and frames-1 or lapsraw[i+1]
    local frameCount = frameEnd - frameBegin
    
    local timeBegin = contentTimes[frameBegin]
    local time      = contentTimes[frameEnd] - timeBegin
    
    print("lap "..(i), frameBegin, frameCount, "time", timeBegin, time)
    table.insert(lapData, { frameBegin = frameBegin, frameCount = frameCount, timeBegin=timeBegin, time=time} )
  end
  
  local begin    = contentTimes[0]
  local duration = contentTimes[frames-1] - begin
  
  local trace = {
    begin  = begin,
    duration = duration,
    frames = frames,
    pollrate = pollrate,
    laps = laps,
    lapData = lapData,
    content = content,
    contentTimes = contentTimes,
    contentSize = contentSize,
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
    ffi.copy(state, content + idx, r3e.SHARED_SIZE)
    return idx
  end
  
  function trace:getFrameRaw(state, idx)
    local idx = math.max(math.min(idx, frames-1),0)
    ffi.copy(state, content + idx, r3e.SHARED_SIZE)
  end
  
  function trace:getInterpolatedFrame(state, time, startidx)
    local idx = trace:getFrameIdx(time, startidx)
    if (idx == frames-1) then
      ffi.copy(state, content + idx, r3e.SHARED_SIZE)
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
