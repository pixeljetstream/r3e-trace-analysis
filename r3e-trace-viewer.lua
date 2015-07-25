local wx = require "wx"
local ffi = require "ffi"
local gl  = require "glewgl"
local glu  = require "glutils"
local utils = require "utils"
local r3e = require "r3e"
local r3etrace = require "r3etrace"
local r3emap   = require "r3emap"
local math3d   = require "math3d"
local v3,v4,m4 = math3d.namespaces.v3,math3d.namespaces.v4,math3d.namespaces.m4

local config       = {record={}, replay={}, viewer={}}
CONFIG = config

utils.loadInto("config.lua", config)
utils.loadInto("config-user.lua", config)

local args = _ARGS or {...}
local APP_NAME  = "R3E Trace Viewer"
local SLIDER_RES = 2048
local AVG_RES    = 2048
local MAX_PLOTS  = 4
---------------------------------------------

local function addTables(tab,n)
  for i=1,n do
    tab[i] = {}
  end
end

local function getNumSelected(selected)
  return selected and #selected.props or 0
end

local function getNumSamples(trace, lap)
  local lap = trace.lapData[lap]
  local timeBegin = lap.timeBegin
  local timeEnd   = lap.timeBegin + lap.time
  local rate      = config.viewer.samplerate or 0.1
  return math.floor((lap.time/rate + 1)/2)*2
end

local function getSampledData(trace, lap, numSamples, times, pos, gradient, selected, outputs)
  local state = ffi.new( r3e.SHARED_TYPE )
  local statePrev = ffi.new( r3e.SHARED_TYPE )
  local stateNext = ffi.new( r3e.SHARED_TYPE )
  
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
  
  local function getMagnitude(res)
    return math.sqrt(res[1]*res[1] + res[2]*res[2] + res[3]*res[3])
  end
  
  local results = {}
  local resultsPrev = {}
  local resultsNext = {}
  
  gradient = (gradient or 0) * 0.5
  
  for n=0,numSamples-1 do
    local time = lap.timeBegin + rate * n
    local laptime = time-timeBegin
    
    trace:getInterpolatedFrame(state, time)
    
    if (times) then
      times[n] = laptime
    end
    -- swizzle pos
    if (pos) then
      pos[n*3+0] = state.Player.Position.X
      pos[n*3+1] = state.Player.Position.Z
      pos[n*3+2] = state.Player.Position.Y
    end
    if (num > 0) then
      if (gradient > 0) then
        trace:getInterpolatedFrame(statePrev, time - gradient * rate)
        trace:getInterpolatedFrame(stateNext, time + gradient * rate)
        selected.fnaccess(resultsPrev, statePrev)
        selected.fnaccess(resultsNext, stateNext)
        for i=1,num do
          local v = selected.props[i]
          local resPrev = resultsPrev[i]
          local resNext = resultsNext[i]
          if (v.descr == "r3e_vec3_f64" or v.descr == "r3e_vec3_f32") then
            resPrev = getMagnitude(resPrev)
            resNext = getMagnitude(resNext)
          end
          local res = resNext-resPrev
          outputs[i][n] = res
          checkMinMax(i,res)
        end
      else
        selected.fnaccess(results, state)
        for i=1,num do
          local v = selected.props[i]
          local res = results[i]
          if (v.descr == "r3e_vec3_f64" or v.descr == "r3e_vec3_f32") then
            res = getMagnitude(res)
          end
          outputs[i][n] = res
          checkMinMax(i,res)
        end
      end
    end
  end
    
  return minmax 
end

local function saveCSV(trace, lap, selected, gradient, filename)
  
  local samples = getNumSamples(trace, lap)
  local num     = getNumSelected(selected)
  
  local times   = {}
  local pos     = {}
  local outputs = {}
  addTables(outputs, num)
  
  getSampledData(trace, lap, samples, times, pos, gradient, selected, outputs)
  
  local f = io.open(filename,"wt")
  f:write('"times"; ')
  for i=1,num do
    f:write('"'..selected.props[i].name..'"; ')
  end
  f:write("\n")
  for n=0,samples-1 do
    f:write(tostring(times[n]))
    f:write("; ")
    for i=1,num do
      f:write(tostring(outputs[i][n]))
      f:write("; ")
    end
    f:write("\n")
  end
  f:flush()
  f:close()
end

---------------------------------------------
local traceFileName = args[2] or args[1]==nil and "trace_150712_170141.r3t"
local trace
local traceLapData
local traceLap   = 1
local traceTime  = 0
local traceState = ffi.new( r3e.SHARED_TYPE )

local app
local function reportStatus(text)
  app:SetStatusText(text)
end

---------------------------------------------

local events = {
  time = {},
  open = {},
  lap = {},
}

local function triggerEvent(tab, trace, lap, time, state)
  for i,v in ipairs(tab) do
    v(trace,lap,frame,state)
  end
end

local function traceSetTime(time)
  traceTime = frame
  trace:getFrame( traceState, time )
  triggerEvent(events.time, trace, traceLap, time, traceState)
end


local function traceSetLap(lap)
  traceLapData = trace.lapData[lap] 
  traceLap = lap
  triggerEvent(events.lap, trace, lap, nil, nil)
  traceSetTime(traceLapData.timeBegin)
end

local function traceSetFile(fileName)
  if not fileName then return end
  
  trace = r3etrace.loadTrace(fileName)
  
  if (trace) then
    app:SetTitle(APP_NAME.." - "..fileName)
    triggerEvent(events.open, trace, nil, nil, nil)
    traceSetLap(1)
  else
    reportStatus("load failed")
  end
end

local function registerHandler(what,handler)
  table.insert(what, handler)
end

local IDCounter = wx.wxID_HIGHEST
local function NewID()
  IDCounter = IDCounter + 1
  return IDCounter
end
local ID_PROPERTY = NewID()
local ID_LAP      = NewID()
local ID_SLIDER   = NewID()
local ID_TXTTIME  = NewID()
local ID_SPNGRAD  = NewID()
local ID_SPNWIDTH = NewID()
local ID_BTNEXPORT= NewID()
local ID_BTNPLOT  = NewID()
local ID_GRAPH    = NewID()
local ID_TRACK    = NewID()
local ID_EXPRESSION = NewID()


---------------------------------------------

local function toMS(seconds)
  local m = math.floor(seconds/60)
  local s = seconds-m*60
  return string.format("%d:%.4f", m,s)
end

local function initLapView(frame)
  
  
  local control = wx.wxListCtrl(frame, ID_LAP,
                            wx.wxDefaultPosition, wx.wxSize(110, 300),
                            wx.wxLC_REPORT + wx.wxLC_SINGLE_SEL)
  
  local default = control:GetTextColour()
  local sel     = wx.wxColour(205,100,0)
  
  local function lapString( i, sel )
    local str = trace.lapData[i].valid and tostring(i) or "("..tostring(i)..")"
    return sel and ""..str.." |||" or str
  end
  
  local lastLap
  local function lap(trace, lap)
    if (lastLap) then
      control:SetItem(lastLap-1, 0, lapString(lastLap,false))
    end
    control:SetItem(lap-1, 0, lapString(lap,true))
    lastLap = lap
  end

  local function open(trace) 
    control:ClearAll()
    control:InsertColumn(0, "Lap")
    control:InsertColumn(1, "Time")
    control:SetColumnWidth(0,40)
    control:SetColumnWidth(1,60)
    for i,v in ipairs(trace.lapData) do
      control:InsertItem(i-1, lapString(i, i==1))
      control:SetItem(i-1, 1, toMS(v.time))
    end
  end
  
  registerHandler(events.lap, lap)
  registerHandler(events.open, open)
  
  return control
end

---------------------------------------------

local function initPropertyView(frame)
  
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
        table.insert(used, allprops[idx])
      end
    end
  end
  
  local fnaccess = r3emap.makeAccessor(props)
  local results = {}
  
  local control = wx.wxListCtrl(frame, ID_PROPERTY,
                            wx.wxDefaultPosition, wx.wxSize(200, 200),
                            wx.wxLC_REPORT)
  control:InsertColumn(0, "Property")
  control:InsertColumn(1, "Value")
  control:SetColumnWidth(0,180)
  control:SetColumnWidth(1,210)
  
  -- create
  for i,v in ipairs(props) do
    control:InsertItem(i-1, v.name)
  end
  
  local function time(trace, lap, time, state) 
    -- update values
    fnaccess(results, state)
    for i,v in ipairs(results) do
      local txt
      if type(v) == "table" then
        local v3length = math.sqrt(v[1]*v[1] + v[2]*v[2] + v[3]*v[3])
        txt = string.format("{%.3f, %.3f, %.3f}  %.3f",v[1],v[2],v[3],v3length)
      else
        txt = tostring(v)
      end
      control:SetItem(i-1, 1, txt)
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
    
    result.fnaccess = r3emap.makeAccessor(result.props)
    
    return result
  end

  registerHandler(events.time, time)
  
  return control
end

---------------------------------------------
local gfx = {
  samplesAvg = nil,
  plot = nil, -- current
  enabled = {true,},
  plots = {}, -- all
  widthmul = 1,
}
do
  local glcontext -- the primary context
  local texheat = ffi.new("GLuint[1]")
  local bufavg  = ffi.new("GLuint[1]")
  
  local function makeTrackPlot()
    return {
      buffers   = ffi.new("GLuint[3]"),
      textures  = ffi.new("GLuint[3]"),
      
      buftimes = nil,
      bufpos  = nil,
      bufdata = nil,
      textimes = nil,
      texpos  = nil,
      texdata = nil,
      
      trace = nil,
      lap = 0,
      samples = 0,
      minmax  = nil,
      prop = nil,
      gradient = true,
    }
  end
  
  for i=1,MAX_PLOTS do
    gfx.plots[i] = makeTrackPlot()
    gfx.plots[i].idx = i
  end
  
  local progTrack 
  local unisTrack
  local progBasic 
  local unisBasic
  
  gfx.plot = gfx.plots[1]
  
  function gfx.createSharedContext(canvas)
    local context 
    if (glcontext) then
      context = wx.wxGLContext(canvas, glcontext)
      
    else
      context = wx.wxGLContext(canvas)
      glcontext = context
      context:SetCurrent(canvas)
      gl.glewInit()
      
      --glu.enabledebug()
      
      -- from http://kennethmoreland.com/color-maps/
      local heatmap = {
        0.2298057,0.298717966,0.753683153,
        0.26623388,0.353094838,0.801466763,
        0.30386891,0.406535296,0.84495867,
        0.342804478,0.458757618,0.883725899,
        0.38301334,0.50941904,0.917387822,
        0.424369608,0.558148092,0.945619588,
        0.46666708,0.604562568,0.968154911,
        0.509635204,0.648280772,0.98478814,
        0.552953156,0.688929332,0.995375608,
        0.596262162,0.726149107,0.999836203,
        0.639176211,0.759599947,0.998151185,
        0.681291281,0.788964712,0.990363227,
        0.722193294,0.813952739,0.976574709,
        0.761464949,0.834302879,0.956945269,
        0.798691636,0.849786142,0.931688648,
        0.833466556,0.860207984,0.901068838,
        0.865395197,0.86541021,0.865395561,
        0.897787179,0.848937047,0.820880546,
        0.924127593,0.827384882,0.774508472,
        0.944468518,0.800927443,0.726736146,
        0.958852946,0.769767752,0.678007945,
        0.96732803,0.734132809,0.628751763,
        0.969954137,0.694266682,0.579375448,
        0.966811177,0.650421156,0.530263762,
        0.958003065,0.602842431,0.481775914,
        0.943660866,0.551750968,0.434243684,
        0.923944917,0.49730856,0.387970225,
        0.89904617,0.439559467,0.343229596,
        0.869186849,0.378313092,0.300267182,
        0.834620542,0.312874446,0.259301199,
        0.795631745,0.24128379,0.220525627,
        0.752534934,0.157246067,0.184115123,
        0.705673158,0.01555616,0.150232812,
      }
      
      local heatdata = ffi.new("float[?]", #heatmap, heatmap)
      
      -- load heatmap
      -- avoid DSA for webgl folks
      gl.glGenTextures (1, texheat)
      texheat = texheat[0]
      gl.glBindTexture (gl.GL_TEXTURE_1D, texheat)
      gl.glTexImage1D  (gl.GL_TEXTURE_1D, 0, gl.GL_RGB16F, #heatmap/3, 0,
        gl.GL_RGB, gl.GL_FLOAT, ffi.cast("GLubyte*",heatdata))
      gl.glTexParameteri(gl.GL_TEXTURE_1D, gl.GL_TEXTURE_MIN_FILTER, gl.GL_LINEAR)
      gl.glTexParameteri(gl.GL_TEXTURE_1D, gl.GL_TEXTURE_MAG_FILTER, gl.GL_LINEAR)
      gl.glTexParameteri(gl.GL_TEXTURE_1D, gl.GL_TEXTURE_WRAP_S, gl.GL_CLAMP_TO_EDGE)
      gl.glBindTexture (gl.GL_TEXTURE_1D, 0)
      
      gl.glGenBuffers(1,bufavg)
      bufavg = bufavg[0]
      
      local function initPlot(t)
        gl.glGenBuffers(3,t.buffers)
        gl.glGenTextures(3,t.textures)
        
        t.buftimes = t.buffers[0]
        t.bufpos   = t.buffers[1]
        t.bufdata  = t.buffers[2]
        t.textimes = t.textures[0]
        t.texpos   = t.textures[1]
        t.texdata  = t.textures[2]
      end
      for i=1,MAX_PLOTS do
        initPlot(gfx.plots[i])
      end
      
      progTrack = glu.loadprogram({
          GL_VERTEX_SHADER = "shaders/track.vert.glsl",
          GL_FRAGMENT_SHADER = "shaders/track.frag.glsl",
        })
      
      unisTrack = glu.programuniforms(progTrack)
      
      progBasic = glu.loadprogram({
          GL_VERTEX_SHADER = "shaders/basic.vert.glsl",
          GL_FRAGMENT_SHADER = "shaders/basic.frag.glsl",
        })
      
      unisBasic = glu.programuniforms(progBasic)
    end
    return context
  end
  
  function gfx.openUpdate(trace)
    -- find first valid lap
    gfx.samplesAvg = nil
    gfx.trace    = trace
    for i,v in ipairs(trace.lapData) do
      if (v.valid) then
        local pos  = ffi.new("float[?]", AVG_RES*3)
        getSampledData(trace, i, AVG_RES, {}, pos)
        
        gl.glNamedBufferDataEXT(bufavg, 4*3*AVG_RES, pos, gl.GL_STATIC_DRAW)
        gfx.samplesAvg = AVG_RES
        break
      end
    end
    
  end
  registerHandler(events.open, gfx.openUpdate)

  function gfx.lapUpdate(trace, lap)
    local plot = gfx.plot
    local samples = getNumSamples(trace, lap)
    
    -- create and fill new buffers
    plot.trace   = trace
    plot.samples = samples
    plot.lap     = lap
    plot.minmax  = nil
    plot.gradient= true
    plot.info    = "Driveline"
    
    local pos    = ffi.new("float[?]", samples*3)
    local times  = ffi.new("float[?]", samples)
    local data   = ffi.new("float[?]", samples,    0)
    
    getSampledData(trace, lap, samples, times, pos)
    
    gl.glNamedBufferDataEXT( plot.bufpos, 4*3*samples, pos, gl.GL_STATIC_DRAW)
    gl.glTextureBufferEXT( plot.texpos, gl.GL_TEXTURE_BUFFER, gl.GL_RGB32F, plot.bufpos)

    gl.glNamedBufferDataEXT( plot.buftimes, 4*samples, times, gl.GL_STATIC_DRAW)
    gl.glTextureBufferEXT( plot.textimes, gl.GL_TEXTURE_BUFFER, gl.GL_R32F, plot.buftimes )
    
    gl.glNamedBufferDataEXT( plot.bufdata, 4*samples, data, gl.GL_STATIC_DRAW)
    gl.glTextureBufferEXT( plot.texdata, gl.GL_TEXTURE_BUFFER, gl.GL_R32F, plot.bufdata )
  end
  registerHandler(events.lap, gfx.lapUpdate)
  
  function gfx.timeUpdate(trace, lap, time, state)
    gfx.pos = {state.Player.Position.X,state.Player.Position.Z,state.Player.Position.Y}
  end
  registerHandler(events.time, gfx.timeUpdate)

  function gfx.propertyUpdate(trace, lap, selected, gradient)
    local plot = gfx.plot
    
    if (getNumSelected(selected)==0) then
      return
    end
    
    if (plot.trace ~= trace or plot.lap ~= lap) then
      gfx.lapUpdate(trace,lap)
    end
    
    local samples = plot.samples
    
    local outputs = {
      ffi.new("float[?]", samples)
    }
    
    local minmax = getSampledData(trace, lap, samples, nil, nil, gradient, selected, outputs)
    
    plot.prop   = selected.props[1]
    plot.minmax = minmax[1]
    plot.gradient = gradient > 0
    
    gl.glNamedBufferSubDataEXT(plot.bufdata, 0, 4*samples, outputs[1])
    
    plot.info = plot.prop.name..string.format(" [ %.2f, %2.f ] ", plot.minmax[1],plot.minmax[2])..(gradient > 0 and " Gradient: "..gradient.." " or "")
    return plot.info
  end
  
  function gfx.drawTrack(w,h,zoom,pan)
    local stride = 1
    
    -- swap y,z
    local range = { gfx.trace.posMax[1]-gfx.trace.posMin[1],
                    gfx.trace.posMax[3]-gfx.trace.posMin[3],
                    gfx.trace.posMax[2]-gfx.trace.posMin[2]}
    local hrange = {range[1]/2,range[2]/2,range[3]/2}
    
    local trackaspect = range[1]/range[2]
    local aspect = w/h
    
    local rotate = trackaspect > aspect and aspect < 1
    trackaspect = rotate and 1/trackaspect or trackaspect
    
    local aspectw
    local aspecth
    
    if (rotate == (aspect > trackaspect)) then
      aspectw = aspect > trackaspect and aspect or 1
      aspecth = aspect > trackaspect and 1 or 1/aspect
    else
      aspectw = aspect < trackaspect and aspect or 1
      aspecth = aspect < trackaspect and 1 or 1/aspect    
    end
    aspectw = aspectw * 1.1
    aspecth = aspecth * 1.1
    
    gl.glDisable(gl.GL_DEPTH_TEST)
    
    local viewProjTM = m4.ortho(m4.float(), -1*aspectw,1*aspectw, -1*aspecth, 1*aspecth, -1, 1)
    local scale = math.max(hrange[1],hrange[2])
    if (rotate) then
      m4.mulA( viewProjTM, m4.rotatedXYZ( m4.tab(), v3.tab(0,0,math.rad(-90)) ))
    end
    m4.mulA( viewProjTM, m4.scaled( m4.tab(), 1/scale, 1/scale, 1/scale ))
    m4.mulA( viewProjTM, m4.translated( m4.tab(),
                    -gfx.trace.posMin[1]-hrange[1],
                    -gfx.trace.posMin[3]-hrange[2],
                    -gfx.trace.posMin[2]-hrange[3]))


    gl.glEnable(gl.GL_SAMPLE_ALPHA_TO_COVERAGE)
    
    local numPlots = 0
    local numRacelines = 0
    local plots = {}
    
    for i=1,MAX_PLOTS do
      if (gfx.enabled[i] and gfx.plots[i].trace) then 
        plots[numPlots+1] = gfx.plots[i]
        numRacelines = numRacelines + (gfx.plots[i].minmax == nil and 1 or 0)
        numPlots = numPlots + 1
      end
    end
    
    local minmaxs = {}
    -- things that are in same coordinate space, should use merged
    -- minmax for graph to be comparable
    for i=1,numPlots do
      local a = plots[i]
      minmaxs[i] = minmaxs[i] or a.minmax
      -- compare with others
      for n=i+1,numPlots do
        local b = plots[n]
        
        if (a.minmax and b.minmax and 
            a.prop and b.prop and
            a.gradient == b.gradient and
          (
            (a.prop.name == b.prop.name) or
            (a.prop.name:match("Temp") ~= nil) == (b.prop.name:match("Temp") ~= nil) or 
            (a.prop.name:match("Pressure") ~= nil) == (b.prop.name:match("Pressure") ~= nil) or
            (a.prop.name:match("Time") ~= nil) == (b.prop.name:match("Time") ~= nil) or
            (a.prop.name:match("Pedal") ~= nil) == (b.prop.name:match("Pedal") ~= nil)
          ))
        then
          local merged = {math.min(a.minmax[1],b.minmax[1]), math.max(a.minmax[2],b.minmax[2])}
          minmaxs[i] = merged
          minmaxs[n] = merged
        end
      end
    end
    
    local curRaceline = 0
    for i=1,numPlots do
      local plot = plots[i]
    
      local dataTM = m4.float()
      
      local isline = plot.minmax == nil

      local minmax = minmaxs[i] or {-1,1}
      local range = math.max(minmax[2],math.abs(minmax[1]))
      if (plot.gradient) then
        -- [-range,range]
        m4.mulA( dataTM, m4.scaled( m4.tab(), 1/(range*2),1,1 ))
        m4.mulA( dataTM, m4.translated( m4.tab(), range,0,0 ) )
      else
        -- [0,range]
        m4.mulA( dataTM, m4.scaled( m4.tab(), 1/range,1,1 ))
      end
      if (isline) then
        local offset = numRacelines > 1 and ((curRaceline)/(numRacelines-1))*1.5-0.75 or -0.5
        m4.mulA( dataTM, m4.translated( m4.tab(), offset,0,0 ) )
      end
      
      local numPoints = math.floor(plot.samples/stride)
      
      gl.glUseProgram(progTrack)
      
      gl.glBindMultiTextureEXT(gl.GL_TEXTURE0, gl.GL_TEXTURE_BUFFER, plot.texpos)
      gl.glBindMultiTextureEXT(gl.GL_TEXTURE1, gl.GL_TEXTURE_BUFFER, plot.texdata)
      gl.glBindMultiTextureEXT(gl.GL_TEXTURE2, gl.GL_TEXTURE_BUFFER, plot.textimes)
      gl.glBindMultiTextureEXT(gl.GL_TEXTURE3, gl.GL_TEXTURE_1D, texheat)
      
      gl.glUniformMatrix4fv( unisTrack.viewProjTM, 1, gl.GL_FALSE, viewProjTM )
      gl.glUniformMatrix4fv( unisTrack.dataTM, 1, gl.GL_FALSE, dataTM)
      
      gl.glUniform4f(unisTrack.color, 1,1,1,1)
      
      if (isline) then
        gl.glUniform1f(unisTrack.shift, 0)
        gl.glUniform1f(unisTrack.width, 6 * gfx.widthmul)
      else
        local width     = numPlots > 1 and 12/numPlots or 10
        local shift     = numPlots > 1 and width*2.5 or 0
        local shiftbase = numPlots > 1 and -((numPlots-1)*shift + width*2)*0.5+width or 0
        gl.glUniform1f(unisTrack.shift, shift * (i-1) + shiftbase)
        gl.glUniform1f(unisTrack.width, width * gfx.widthmul)
      end
      
      if (isline) then
        local width = 0.7 --1/numRacelines
        local start = i*0.5
        gl.glUniform4f(unisTrack.timecontrol, 1, start, width, 0)
      else
        gl.glUniform4f(unisTrack.timecontrol, 1,1,1,1)
      end
      
      gl.glUniform1i(unisTrack.numPoints, numPoints)
      
      gl.glDrawArrays(gl.GL_TRIANGLE_STRIP, 0, numPoints * 2)
      
      gl.glDisableVertexAttribArray(0)
      gl.glDisableVertexAttribArray(1)
      
      gl.glBindMultiTextureEXT(gl.GL_TEXTURE0, gl.GL_TEXTURE_BUFFER, 0)
      gl.glBindMultiTextureEXT(gl.GL_TEXTURE1, gl.GL_TEXTURE_BUFFER, 0)
      gl.glBindMultiTextureEXT(gl.GL_TEXTURE2, gl.GL_TEXTURE_BUFFER, 0)
      gl.glBindMultiTextureEXT(gl.GL_TEXTURE3, gl.GL_TEXTURE_1D, 0)
      
      if (isline) then
        curRaceline = curRaceline + 1
      end
    end
    
    if (gfx.samplesAvg) then
      
      local samples = gfx.samplesAvg
      local buf     = bufavg
      
      gl.glEnable(gl.GL_POINT_SMOOTH)
    
      gl.glUseProgram(progBasic)
      gl.glUniformMatrix4fv( unisBasic.viewProjTM, 1, gl.GL_FALSE, viewProjTM)
    
      local clr = 0.3
      gl.glUniform4f(unisBasic.color, clr,clr,clr,1)
      
      gl.glLineWidth(1.5)
      gl.glBindBuffer(gl.GL_ARRAY_BUFFER, buf)
      gl.glVertexAttribPointer(0, 3, gl.GL_FLOAT, gl.GL_FALSE, 4*3, nil)
      gl.glEnableVertexAttribArray(0)
      
      gl.glDrawArrays(gl.GL_LINE_STRIP, 0, samples)
      
      gl.glDisableVertexAttribArray(0)
      
      gl.glUniform4f(unisBasic.color, 0,0,0,1)
      gl.glPointSize(16)
      gl.glBegin(gl.GL_POINTS)
      gl.glVertexAttrib3f(0, gfx.pos[1], gfx.pos[2], gfx.pos[3])
      gl.glEnd()
      
      gl.glDisable(gl.GL_POINT_SMOOTH)
    end
  end
end
---------------------------------------------

local function initTrackView(frame)
  local init = true

  local canvas = wx.wxGLCanvas(frame, wx.wxID_ANY, {
  wx.WX_GL_RGBA, 1, wx.WX_GL_DOUBLEBUFFER, 1, 
  wx.WX_GL_MIN_RED, 8, wx.WX_GL_MIN_GREEN, 8, wx.WX_GL_MIN_BLUE, 8, wx.WX_GL_MIN_ALPHA, 8,
  wx.WX_GL_STENCIL_SIZE, 0, wx.WX_GL_DEPTH_SIZE, 0
  },
  wx.wxDefaultPosition, wx.wxDefaultSize, wx.wxEXPAND + wx.wxFULL_REPAINT_ON_RESIZE)

  --local lbl = wx.wxTextCtrl(canvas, wx.wxID_ANY, "Blah",wx.wxDefaultPosition, wx.wxSize(78,24), wx.wxTE_READONLY)
  local lbl = wx.wxStaticText(canvas, wx.wxID_ANY, " No Data ")
  canvas.lbl = lbl

  local context = gfx.createSharedContext(canvas)
  
  local res = ffi.new("GLuint[1]")
  gl.glGenTextures(1, res)
  local tex = res[0]
  gl.glGenFramebuffers(1, res)
  local fbo = res[0]
  
  local lastw,lasth
  
  local function render()
    
    context:SetCurrent(canvas)
    
    local sz = canvas:GetSize()
    local w,h = sz:GetWidth(), sz:GetHeight()
    
    gl.glBindFramebuffer( gl.GL_FRAMEBUFFER, fbo)
    
    if (lastw ~= w or lasth ~= h) then
      gl.glBindTexture(gl.GL_TEXTURE_2D_MULTISAMPLE, tex)
      gl.glTexImage2DMultisample(gl.GL_TEXTURE_2D_MULTISAMPLE, config.viewer.msaa or 8,
        gl.GL_RGBA8, w, h, gl.GL_FALSE)
      gl.glFramebufferTexture2D(gl.GL_FRAMEBUFFER, gl.GL_COLOR_ATTACHMENT0, 
        gl.GL_TEXTURE_2D_MULTISAMPLE, tex, 0)
      
      lastw = w
      lasth = h
    end
   
    gl.glViewport(0,0,w,h)

    gl.glClearDepth(1)
    gl.glClearStencil(0)
    gl.glClearColor(1, 1, 1, 1)
    gl.glClear(gl.GL_COLOR_BUFFER_BIT + gl.GL_DEPTH_BUFFER_BIT + gl.GL_STENCIL_BUFFER_BIT)
    
    if (gfx.trace) then 
      gfx.drawTrack(w,h,zoom,pan)
    end

    gl.glBindFramebuffer( gl.GL_DRAW_FRAMEBUFFER, 0)
    gl.glBlitFramebuffer( 0,0, w, h, 0,0, w, h, gl.GL_COLOR_BUFFER_BIT, gl.GL_LINEAR)
    canvas:SwapBuffers()
  end
  
  function canvas.changed()
    local txt = ""
    local first = true
    local num = 0
    for i=1,MAX_PLOTS do
      if (gfx.enabled[i] and gfx.plots[i].trace) then
        local plot = gfx.plots[i]
        txt = txt..(first and "" or "\n").." Lap "..plot.lap.." "..plot.info
        first = false
        num = num + 1
      end
    end
    if (num > 1) then
      txt = "Plot order left to right:\n"..txt
    end
    lbl:SetLabel(txt)
    canvas:Refresh()
  end
  
  canvas:Connect(wx.wxEVT_PAINT, render)
  --canvas:Connect(wx.wxEVT_SIZE,  render)
  
  registerHandler(events.time, function() canvas.changed() end)
  
  return canvas
end

---------------------------------------------
local function initApp()
  local frame = wx.wxFrame(wx.NULL, wx.wxID_ANY, APP_NAME,
  wx.wxDefaultPosition, wx.wxSize(1024, 768), wx.wxDEFAULT_FRAME_STYLE)

  -- create a simple file menu
  local fileMenu = wx.wxMenu()
  fileMenu:Append(wx.wxID_OPEN, "&Open", "Open Trace file")
  fileMenu:Append(wx.wxID_EXIT, "E&xit", "Quit the program")

  -- create a simple help menu
  local helpMenu = wx.wxMenu()
  helpMenu:Append(wx.wxID_ABOUT, "&About", "About the wxLua Minimal Application")

  -- create a menu bar and append the file and help menus
  local menuBar = wx.wxMenuBar()
  menuBar:Append(fileMenu, "&File")
  menuBar:Append(helpMenu, "&Help")

  -- attach the menu bar into the frame
  frame:SetMenuBar(menuBar)

  -- create a simple status bar
  frame:CreateStatusBar(1)
  frame:SetStatusText("Welcome.")

  -- connect the selection event of the exit menu item to an
  -- event handler that closes the window
  frame:Connect(wx.wxID_EXIT, wx.wxEVT_COMMAND_MENU_SELECTED,
    function (event) frame:Close() end )
              
  -- open file dialog
  frame:Connect(wx.wxID_OPEN, wx.wxEVT_COMMAND_MENU_SELECTED,
    function (event) 
      local fileDialog = wx.wxFileDialog( frame, "Open file", "", "","R3E trace files (*.r3t)|*.r3t",
                                          wx.wxFD_OPEN + wx.wxFD_FILE_MUST_EXIST)

      if fileDialog:ShowModal() == wx.wxID_OK then
        traceSetFile(fileDialog:GetPath())
      end
      fileDialog:Destroy()
    end )

  -- connect the selection event of the about menu item
  frame:Connect(wx.wxID_ABOUT, wx.wxEVT_COMMAND_MENU_SELECTED,
    function (event)
      wx.wxMessageBox('R3E Trace Viewer\n(c) 2015 Christoph Kubisch',
                      "About R3E Trace Viewer",
                      wx.wxOK + wx.wxICON_INFORMATION,
                      frame)
    end )
  
  local tools       = wx.wxPanel( frame, wx.wxID_ANY )
  local toolsTime   = wx.wxWindow ( tools, wx.wxID_ANY )
  local toolsAction = wx.wxWindow ( tools, wx.wxID_ANY )
  local sizer = wx.wxBoxSizer(wx.wxVERTICAL)
  sizer:Add(toolsAction, 0, wx.wxEXPAND)
  sizer:Add(toolsTime, 0, wx.wxEXPAND)
  tools:SetSizer(sizer)
  
  frame.tool = tools
  
  local lbltime = wx.wxStaticText(toolsTime, wx.wxID_ANY, "Time:", wx.wxDefaultPosition, wx.wxSize(30,24), wx.wxALIGN_RIGHT)
  local txttime = wx.wxTextCtrl(toolsTime, ID_TXTTIME, "0", wx.wxDefaultPosition, wx.wxSize(78,24), wx.wxTE_READONLY)
  local slider  = wx.wxSlider(toolsTime, ID_SLIDER, 0, 0, SLIDER_RES, wx.wxDefaultPosition, wx.wxSize(80,24))
  
  -- wx.wxArtProvider.GetBitmap(wx.wxART_REPORT_VIEW, wx.wxART_MENU, wx.wxSize(16,16))
  local btnexport = wx.wxButton( toolsAction, ID_BTNEXPORT, "Export Sel. Props",wx.wxDefaultPosition, wx.wxSize(116,24))
  btnexport:SetToolTip("Export selected properties to .csv")
  local btnplot = wx.wxButton( toolsAction, ID_BTNPLOT, "Plot Sel. Props",wx.wxDefaultPosition, wx.wxSize(100,24))
  local lblgrad = wx.wxStaticText(toolsAction, wx.wxID_ANY, "Gradient:", wx.wxDefaultPosition, wx.wxSize(56,24), wx.wxALIGN_RIGHT)
  local spngrad = wx.wxSpinCtrl(toolsAction, ID_SPNGRAD, "", wx.wxDefaultPosition, wx.wxSize(50,24))
  
  local lblplot = wx.wxStaticText(toolsAction, wx.wxID_ANY, "Selector", wx.wxDefaultPosition, wx.wxSize(50,24), wx.wxALIGN_RIGHT)
  local lblvis  = wx.wxStaticText(toolsAction, wx.wxID_ANY, "Visible", wx.wxDefaultPosition, wx.wxSize(40,24), wx.wxALIGN_RIGHT)
  
  local spnwidth = wx.wxSpinCtrl(toolsAction, ID_SPNWIDTH, "", wx.wxDefaultPosition, wx.wxSize(60,24),
    wx.wxSP_ARROW_KEYS, 1, 100, 10)
  
  local radios = {}
  for i=1,MAX_PLOTS do
    local id  = NewID()
    local rad = wx.wxRadioButton(toolsAction, id, string.char(64+i), wx.wxDefaultPosition, wx.wxDefaultSize,  i==1 and wx.wxRB_GROUP or 0)
    rad.id = id
    radios[i] = rad
  end
  local checks = {}
  for i=1,MAX_PLOTS do
    local id  = NewID()
    local chk = wx.wxCheckBox(toolsAction, id, string.char(64+i), wx.wxDefaultPosition, wx.wxDefaultSize)
    if (i == 1) then chk:SetValue(true) end
    chk.id = id
    checks[i] = chk
  end
  frame.btnexport = btnexport
  frame.btnplot = btnplot
  frame.lbltime = lbltime
  frame.txttime = txttime
  frame.lblgrad = lblgrad
  frame.spngrad = spngrad
  frame.slider  = slider
  frame.radios  = radios
  frame.checks  = checks
  
  local sizer = wx.wxBoxSizer(wx.wxHORIZONTAL)
  sizer:Add(lbltime, 0, wx.wxALL,4)
  sizer:Add(txttime, 0, wx.wxALL)
  sizer:Add(slider, 1, wx.wxEXPAND)
  toolsTime:SetSizer(sizer)
  
  local sizer = wx.wxBoxSizer(wx.wxHORIZONTAL)
  sizer:Add(btnexport, 0, wx.wxALL)
  sizer:Add(btnplot, 0, wx.wxALL)
  sizer:Add(lblgrad, 0, wx.wxALL,4)
  sizer:Add(spngrad, 0, wx.wxALL)
  sizer:Add(lblplot, 0, wx.wxALL,4)
  for i,v in ipairs(radios) do
    sizer:Add(v, 0, wx.wxALL, 4)
  end
  sizer:Add(lblvis, 0, wx.wxALL,4)
  for i,v in ipairs(checks) do
    sizer:Add(v, 0, wx.wxALL, 4)
  end
  sizer:Add(spnwidth, 0, wx.wxALL)
  toolsAction:SetSizer(sizer)
  
  local lapSplitter = wx.wxSplitterWindow( frame, wx.wxID_ANY )
  frame.lapSplitter = lapSplitter
  
  -- Put them in a vertical sizer, with ratio 3 units for the text entry, 5 for button
  -- and padding of 6 pixels.
  local sizer = wx.wxBoxSizer(wx.wxVERTICAL)
  sizer:Add(tools,0, wx.wxEXPAND)
  sizer:Add(lapSplitter,1, wx.wxEXPAND)
  frame:SetSizer(sizer)
  
  -- add lap sidebar
  local lap = initLapView(lapSplitter)
  frame.lap = lap
  
  -- add property
  local propSplitter = wx.wxSplitterWindow( lapSplitter, wx.wxID_ANY )
  frame.propSplitter = propSplitter
  
  local props = initPropertyView(propSplitter)
  frame.props = props
  
  --local trackview = wx.wxPanel( propSplitter, wx.wxID_ANY)
  local trackview = initTrackView(propSplitter)
  frame.trackview = trackview
  
  lapSplitter:SplitVertically(lap,propSplitter)
  propSplitter:SplitVertically(props,trackview)
  
  ----------
  -- events
  
  local function timelap()
    -- reset
    slider:SetValue(0)
    txttime:ChangeValue("0")
  end
  registerHandler(events.lap, timelap)
  
  local function setVisible(i, state)
    checks[i]:SetValue(state)
    gfx.enabled[i] = state
  end
  
  frame:Connect(ID_LAP, wx.wxEVT_COMMAND_LIST_ITEM_ACTIVATED,
  function (event)
    if (not trace) then return end

    setVisible(gfx.plot.idx, true)
    traceSetLap( event:GetIndex()+1)
  end)

  tools:Connect(ID_SPNWIDTH, wx.wxEVT_COMMAND_SPINCTRL_UPDATED,
  function(event)
    gfx.widthmul = spnwidth:GetValue()/10
    trackview:Refresh()
  end)
  
  tools:Connect(ID_SLIDER, wx.wxEVT_COMMAND_SLIDER_UPDATED,
  function (event)
    if (not traceLapData) then return end
    
    local fracc = event:GetInt()/(SLIDER_RES-1)
    local laptime = traceLapData.time * fracc
    local time = traceLapData.timeBegin + laptime
    
    traceSetTime(time)
    txttime:ChangeValue(toMS(laptime))
  end)

  for i=1,MAX_PLOTS do
    local chk = checks[i].id
    local rad = radios[i].id
    tools:Connect(chk, wx.wxEVT_COMMAND_CHECKBOX_CLICKED,
      function (event)
        gfx.enabled[i] = event:IsChecked()
        
        trackview.changed()
      end)
    tools:Connect(rad, wx.wxEVT_COMMAND_RADIOBUTTON_SELECTED,
      function (event)
        gfx.plot = gfx.plots[i]
      end)
  end

  props:Connect(ID_PROPERTY, wx.wxEVT_COMMAND_LIST_ITEM_ACTIVATED,
    function (event)
      local active = gfx.plot.idx
      
      setVisible(active, true)
      
      gfx.propertyUpdate(trace, traceLap, props.getSelected(1), spngrad:GetValue())
      trackview.changed()
    end)

  tools:Connect(ID_BTNPLOT, wx.wxEVT_COMMAND_BUTTON_CLICKED,
    function (event)
      local selected = props.getSelected(4)
      local num = getNumSelected(selected)
      local active = gfx.plot.idx
      
      for i=1,MAX_PLOTS do
        setVisible(i, false)
      end
      
      if (num == 1) then
        setVisible(active, true)
        gfx.propertyUpdate(trace, traceLap, selected, spngrad:GetValue())
      elseif( num > 1) then
        for i=1,num do
          local sel = {props={ selected.props[i] }, }
          sel.fnaccess = r3emap.makeAccessor(sel.props)
          
          gfx.plot = gfx.plots[i]
          setVisible(i, true)
          
          local res = gfx.propertyUpdate(trace, traceLap, sel, spngrad:GetValue())
        end
        gfx.plot = gfx.plots[active]
        
      end
      trackview.changed()
    end)
    
  tools:Connect(ID_BTNEXPORT, wx.wxEVT_COMMAND_BUTTON_CLICKED,
    function (event) 
      local fileDialog = wx.wxFileDialog( frame, "Open file", "", "","CSV table (*.csv)|*.csv",
                                          wx.wxFD_SAVE)

      if fileDialog:ShowModal() == wx.wxID_OK then
        saveCSV( trace, traceLap, props.getSelected(), spngrad:GetValue(), fileDialog:GetPath() )
      end
      fileDialog:Destroy()
    end )
  
  return frame
end



app = initApp()

traceSetFile(traceFileName)

-- show the frame window
app:Show(true)
wx.wxGetApp():MainLoop()