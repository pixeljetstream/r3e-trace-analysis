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
local constants = gCONSTANTS
local reportStatus = gAPP.reportStatus

--------------------------------

local helpers = {}
gHELPERS = helpers

--------------------------------


function helpers.toMS(seconds)
  local m = math.floor(seconds/60)
  local s = seconds-m*60
  return string.format("%d : %.3f", m,s)
end

function helpers.getNumSelected(selected)
  return selected and #selected.props or 0
end

function helpers.getNumSamples(trace, lap)
  local lap = trace.lapData[lap]
  local timeBegin = lap.timeBegin
  local timeEnd   = lap.timeBegin + lap.time
  local rate      = config.viewer.samplerate or 0.1
  return math.floor((lap.time/rate + 1)/2)*2
end

local anglethresh = config.viewer.convertvalues and 180 or math.pi
local function computeGradient(prop, resPrev, resNext)
  if (prop.nonumber) then return 0 end
  if (prop.angle) then
    if (math.abs(resNext-resPrev) > anglethresh) then
      resNext = resNext + (resNext < 0 and (anglethresh*2) or 0)
      resPrev = resPrev + (resPrev < 0 and (anglethresh*2) or 0)
    end
  end
  return resNext-resPrev
end
helpers.computeGradient = computeGradient

function helpers.getTraceShortName(trace)
  return trace.filename:match("([^/\\]+)$")
end

function helpers.getSampledData(trace, lap, numSamples, times, pos, gradient, selected, outputs)
  local state     = ffi.new( constants.SHARED_TYPE )
  local statePrev = ffi.new( constants.SHARED_TYPE )
  local stateNext = ffi.new( constants.SHARED_TYPE )
  
  local lap = trace.lapData[lap]
  
  local timeBegin = lap.timeBegin
  local timeEnd   = lap.timeBegin + lap.time
  local rate      = lap.time/(numSamples-1)
  
  local minmax  = {}
  local num     = outputs and #outputs or 0
  for i=1,num do
    minmax[i]  = {10000000,-1000000}
  end
  
  local function checkMinMax(i,res)
    minmax[i][1] = math.min(minmax[i][1], res)
    minmax[i][2] = math.max(minmax[i][2], res)
  end
  
  local results = {}
  local resultsPrev = {}
  local resultsNext = {}
  
  gradient = (gradient and gradient/100 or 0) * 0.5
  
  for n=0,numSamples-1 do
    local time = lap.timeBegin + rate * n
    local laptime = time-timeBegin
    
    trace:getInterpolatedFrame(state, time)
    
    if (times) then
      times[n] = laptime
    end
    -- swizzle pos
    if (pos) then
      local x,y,z = r3emap.getPosition(state)
      pos[n*4+0] = x
      pos[n*4+1] = y
      pos[n*4+2] = z
      pos[n*4+3] = 1
    end
    if (num > 0) then
      if (gradient > 0) then
        trace:getInterpolatedFrame(statePrev, time - gradient)
        trace:getInterpolatedFrame(stateNext, time + gradient)
        selected.fnaccess(resultsPrev, statePrev)
        selected.fnaccess(resultsNext, stateNext)
        for i=1,num do
          local res = computeGradient(selected.props[i], resultsPrev[i], resultsNext[i])
          outputs[i][n] = res
          checkMinMax(i,res)
        end
  
        selected.fnaccess(results, state)
        for i=1,num do
          local res = selected.props[i].nonumber and 0 or tonumber(results[i]) or 0
          outputs[i][n] = res
          checkMinMax(i, res)
        end
      end
    end
  end
    
  return minmax 
end

function helpers.getProps(convert)
  local allprops = r3emap.getAllProperties()
  local props = allprops
  
  if (config.viewer.dumpfilter) then
    -- get properties
    
    local lkprops = {}
    for i,v in ipairs(allprops) do
      lkprops[v[1]] = i
    end
    -- find 
    props = {}
    for i,v in ipairs(config.replay.dumpfilter) do
      local idx = lkprops[v] 
      if (idx) then
        table.insert(props, allprops[idx])
      end
    end
  end
  
  local fnaccess = r3emap.makeAccessor(props, convert)
  
  return props,fnaccess
end

function helpers.computeAllLapStats(trace)
  local props,fnaccess = helpers.getProps(config.viewer.convertvalues)
  
  local num     = #props
  local results = {}
  
  for i,v in ipairs(trace.lapData) do
    local minmax  = {}
    local avg     = {}
    
    for i=1,num do
      minmax[i]  = {10000000,-1000000}
      avg[i]     = 0
    end
    
    local numFrames = v.frameCount
    local frameEnd  = v.frameBegin + v.frameCount - 1
    
    for f=v.frameBegin,frameEnd do
      local state = trace.content + f
      fnaccess(results,state)
      for i=1,num do
        local res = props[i].nonumber and 0 or tonumber(results[i]) or 0
        --assert(type(res) == "number", props[i].name)
        minmax[i][1] = math.min(minmax[i][1], res)
        minmax[i][2] = math.max(minmax[i][2], res)
        avg[i]       = avg[i] + res
      end
    end
    
    for i=1,num do
      avg[i]     = avg[i]/numFrames
    end
    
    v.avg = avg
    v.minmax = minmax
    
  end
end

function helpers.saveCSV(trace, lap, selected, gradient, filename)
  
  local samples = helpers.getNumSamples(trace, lap)
  local num     = helpers.getNumSelected(selected)
  
  local times   = {}
  local pos     = {}
  local outputs = {}
  for i=1,num do
    outputs[i] = {}
  end
  
  helpers.getSampledData(trace, lap, samples, times, pos, gradient, selected, outputs)
  
  local f = io.open(filename,"wt")
  f:write('"Time", ')
  for i=1,num do
    f:write('"'..selected.props[i].name..'", ')
  end
  f:write("\n")
  for n=0,samples-1 do
    f:write(tostring(times[n]))
    f:write(", ")
    for i=1,num do
      f:write(tostring(outputs[i][n]))
      f:write(", ")
    end
    f:write("\n")
  end
  f:flush()
  f:close()
  
  reportStatus("saved CSV "..filename)
end

function helpers.saveSessionCSV(traces, filename)
  local props, fnaccess = helpers.getProps(false)
  local num = #props
  
  local f = io.open(filename,"wt")
  f:write('"Time", ')
  for i=1,num do
    f:write('"'..props[i].name..'", ')
  end
  f:write("\n")
  
  local results = {}
  
  local lastTime = 0
  
  for t,trace in ipairs(traces) do
    local frames = trace.frames
    local content = trace.content
    
    local baseTime = r3emap.getTime(content[0])
    local delta    = r3emap.getTime(content[1])- baseTime
    
    local time = 0
    for n=0,frames-1 do
      local state = content + n
      fnaccess(results,state)
      time = r3emap.getTime(state) - baseTime + lastTime
      f:write( tostring(time) )
      f:write(", ")
      for i=1,num do
        f:write(tostring(results[i]))
        f:write(", ")
      end
      f:write("\n")
    end
    
    lastTime = time + delta
  end
  
  f:flush()
  f:close()
  
  reportStatus("saved CSV "..filename)
end

return helpers