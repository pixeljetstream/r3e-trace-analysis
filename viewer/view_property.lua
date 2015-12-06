local wx = require "wx"
local ffi = require "ffi"
local gl  = require "glewgl"
local glu  = require "glutils"
local utils = require "utils"
local r3e = require "r3e"
local r3etrace = require "r3etrace"
local math3d   = require "math3d"
local v3,v4,m4 = math3d.namespaces.v3,math3d.namespaces.v4,math3d.namespaces.m4
local config = gCONFIG
local r3emap = gR3EMAP
local helpers = gHELPERS
local sys     = gSYS

local computeGradient = helpers.computeGradient

--------------------------

local function initPropertyView(frame, ID_PROPERTY)
  local props,fnaccess = helpers.getProps(config.viewer.convertvalues)
  local numProps = #props
  
  local results = {}
  local resultsPrev = {}
  local resultsNext = {}
  
  local control = wx.wxListCtrl(frame, ID_PROPERTY,
                            wx.wxDefaultPosition, wx.wxSize(250, 200),
                            wx.wxLC_REPORT)
  control:InsertColumn(0, "Property")
  control:InsertColumn(1, "Value")
  control:InsertColumn(2, "LapMin")
  control:InsertColumn(3, "LapMax")
  control:InsertColumn(4, "LapAvg")
  control:InsertColumn(5, "Gradient")
  local gradColumn = 5
  control:SetColumnWidth(0,180)
  local vwidth = 70
  control:SetColumnWidth(1,vwidth)
  control:SetColumnWidth(2,vwidth)
  control:SetColumnWidth(3,vwidth)
  control:SetColumnWidth(4,vwidth)
  control:SetColumnWidth(5,vwidth)
  
  
  -- create
  for i,v in ipairs(props) do
    control:InsertItem(i-1, v.name)
  end
  
  local function fmtValue(prop, v)
    local txt
    if( prop.interpolate) then
      txt = string.format("%.3f",v)
    else
      txt = tostring(v)
    end
    return txt
  end
  
  local function time(trace, lap, time, state, gradActive, statePrev, stateNext) 
    -- update values
    fnaccess(results, state)
    if (gradActive) then
      fnaccess(resultsPrev, statePrev)
      fnaccess(resultsNext, stateNext)
    end
    for i,v in ipairs(results) do
      local txt = fmtValue(props[i], v)
      control:SetItem(i-1, 1, txt)
      if (gradActive) then
        local res = computeGradient(props[i], resultsPrev[i], resultsNext[i])
        local txt = fmtValue(props[i], res)
        control:SetItem(i-1, gradColumn, txt)
      else
        control:SetItem(i-1, gradColumn, "")
      end
    end
  end
  
  local function lap(trace, lap)
    local lap = trace.lapData[lap]
    
    for i=1,numProps do
      control:SetItem(i-1, 2, fmtValue(props[i], lap.minmax[i][1]))
      control:SetItem(i-1, 3, fmtValue(props[i], lap.minmax[i][2]))
      control:SetItem(i-1, 4, fmtValue(props[i], lap.avg[i]))
    end
  end
  
  function control.getSelected(num)
    local result = {
      props = {},
      fnaccess = nil,
    }
    -- built prop table
    for i,v in ipairs(props) do
      if (control:GetItemState(i-1, wx.wxLIST_STATE_SELECTED) ~= 0) then
        table.insert(result.props, v)
        if (num and #result.props == num) then
          break
        end
      end
    end
    
    result.fnaccess = r3emap.makeAccessor(result.props, config.viewer.convertvalues)
    
    return result
  end

  sys.registerHandler(sys.events.time, time)
  sys.registerHandler(sys.events.lap,  lap)
  
  return control
end

return initPropertyView