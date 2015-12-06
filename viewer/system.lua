local wx = require "wx"
local ffi = require "ffi"
local gl  = require "glewgl"
local glu  = require "glutils"
local utils = require "utils"
local r3e = require "r3e"
local r3etrace = require "r3etrace"
local config = gCONFIG
local r3emap = gR3EMAP
local helpers  = gHELPERS
local reportStatus = gAPP.reportStatus
local constants = gCONSTANTS

local fulldata = config.viewer.fulldata

---------------------------------------------

local sys = {}
gSYS = sys

---------------------------------------------

local events = {
  time = {},
  open = {},
  append = {},
  lap = {},
  range = {},
  property = {},
  compare = {},
}

sys.events = events

---------------------------------------------
local active = {
  filename = nil,
  lap = 0,
  time = 0,
  state     = ffi.new( constants.SHARED_TYPE ),
  statePrev = ffi.new( constants.SHARED_TYPE ),
  stateNext = ffi.new( constants.SHARED_TYPE ),
  lapData = nil,
  trace = nil,
  gradient = 0,
  traces = {},
}

sys.active = active

local function triggerEvent(tab, ...)
  for i,v in ipairs(tab) do
    v(...)
  end
end
sys.triggerEvent = triggerEvent

local function traceSetTime( time )
  active.time = time
  
  local gradient = (active.gradient/100) * 0.5
  active.trace:getInterpolatedFrame( active.state, time )
  active.trace:getInterpolatedFrame( active.statePrev, time - gradient)
  active.trace:getInterpolatedFrame( active.stateNext, time + gradient)
  
  triggerEvent(events.time, active.trace, active.lap, time, active.state, active.gradient > 0, active.statePrev, active.stateNext)
  reportStatus("time set")
end
sys.traceSetTime = traceSetTime

function sys.traceSetGradient( gradient)
  active.gradient = gradient
  traceSetTime(active.time)
  reportStatus("gradient set")
end

function sys.traceSetLap(trace, lap)
  active.trace   = trace
  active.lapData = trace.lapData[lap] 
  active.lap     = lap
  triggerEvent(events.lap, trace, lap, nil, nil)
  traceSetTime(active.lapData.timeBegin)
  reportStatus("lap selection")
end

function sys.traceSetProperty(selected, gradient)
  triggerEvent(events.property, active.trace, active.lap, selected, gradient)
  reportStatus("property selection")
end

function sys.traceSessionSaveCSV(filename)
  helpers.saveSessionCSV(active.traces, filename)
end

function sys.traceSaveCSV(selected, gradient, filename)
  helpers.saveCSV(active.trace, active.lap, selected, gradient, filename)
end

function sys.traceOpenFile(fileName)
  if not fileName then return end
  
  local trace = r3etrace.loadTrace(fileName)
  
  if (trace and trace.fulldata ~= fulldata) then
    return reportStatus("load failed, fulldata state in file must match viewer config")
  end
  
  if (trace) then
    gAPP.app:SetTitle(constants.APP_NAME.." - "..fileName)
    helpers.computeAllLapStats(trace)
    triggerEvent(events.open, trace, nil, nil, nil)
    sys.traceSetLap(trace, 1)
    
    active.traces = {trace}
    reportStatus("loaded "..fileName)
  else
    reportStatus("load failed")
  end
end

function sys.traceAppendFile(fileName)
  if not fileName then return end
  
  local trace = r3etrace.loadTrace(fileName)
  if (trace) then
    helpers.computeAllLapStats(trace)
    triggerEvent(events.append, trace, nil, nil, nil)
    table.insert(active.traces, trace)
    reportStatus("appended "..fileName)
  else
    reportStatus("append failed")
  end
end

function sys.registerHandler(what,handler)
  table.insert(what, handler)
end

local IDCounter = wx.wxID_HIGHEST
function sys.NewID()
  IDCounter = IDCounter + 1
  return IDCounter
end

return sys