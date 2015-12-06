local wx = require "wx"
local ffi = require "ffi"
local gl  = require "glewgl"
local glu  = require "glutils"
local utils = require "utils"
local r3e = require "r3e"
local r3etrace = require "r3etrace"
local math3d   = require "math3d"
local v3,v4,m4 = math3d.namespaces.v3,math3d.namespaces.v4,math3d.namespaces.m4
local config  = gCONFIG
local r3emap  = gR3EMAP
local helpers = gHELPERS
local sys     = gSYS

local toMS = helpers.toMS

---------------------------------------------



local function initLapView(frame, ID_LAP)
  
  
  local control = wx.wxListCtrl(frame, ID_LAP,
                            wx.wxDefaultPosition, wx.wxSize(110, 300),
                            wx.wxLC_REPORT + wx.wxLC_SINGLE_SEL)
  
  local function lapString( trace, i, sel )
    local str = trace.lapData[i].valid and tostring(i) or "("..tostring(i)..")"
    return sel and ""..str.." ||" or str
  end
  
  local content = {}
  local lktrace = {}
  
  local lastTrace
  local lastLap
  local lastIdx
  local function lap(trace, lap)
    local idx = lktrace[trace] + lap - 1
    
    if (lastLap) then
      control:SetItem(lastIdx, 0, lapString(lastTrace,lastLap,false))
    end
    control:SetItem(idx, 0, lapString(trace,lap,true))
    
    lastTrace = trace
    lastLap = lap
    lastIdx = idx
  end
  
  local function append(trace)
    local offset = #content
    lktrace[trace] = offset
    
    for i,v in ipairs(trace.lapData) do
      local idx = offset + i - 1
      
      control:InsertItem(idx, lapString(trace, i))
      control:SetItem(idx, 1, toMS(v.time))
      control:SetItem(idx, 2, helpers.getTraceShortName(trace))
      
      content[idx] = {trace, i}
    end
  end

  local function open(trace) 
    lastLap = nil
    content = {}
    lktrace = {}
    control:ClearAll()
    control:InsertColumn(0, "Lap")
    control:InsertColumn(1, "Time")
    control:InsertColumn(2, "File")
    control:SetColumnWidth(0,36)
    control:SetColumnWidth(1,60)
    control:SetColumnWidth(2,200)
    
    append(trace)
  end
  
  function control.getFromIdx(idx)
    local trace, lap = content[idx][1],content[idx][2]
    return trace,lap
  end
  
  sys.registerHandler(sys.events.lap, lap)
  sys.registerHandler(sys.events.open, open)
  sys.registerHandler(sys.events.append, append)
  
  return control
end

return initLapView