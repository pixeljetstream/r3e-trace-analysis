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
local constants = gCONSTANTS
local sys = gSYS

---------------------------------

local gfx = {
  samplesAvg = nil,
  plot = nil, -- current
  enabled = {true,},
  plots = {}, -- all
  widthmul = 1,
}

gGFX = gfx

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
  
  for i=1,constants.MAX_PLOTS do
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
      
      assert(gl.__GLEW_VERSION_3_3 ~=0,             "OpenGL 3.3 capable hardware and driver required")
      
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
      for i=1,constants.MAX_PLOTS do
        initPlot(gfx.plots[i])
      end
      
      progTrack = glu.loadprogram({
          GL_VERTEX_SHADER = "shaders/track.vert.glsl",
          GL_FRAGMENT_SHADER = "shaders/track.frag.glsl",
        })
      assert(progTrack, "could not load shaders/track")
      unisTrack = glu.programuniforms(progTrack)
      
      gl.glUseProgram(progTrack)
      gl.glUniform1i(unisTrack.texPos,0)
      gl.glUniform1i(unisTrack.texData,1)
      gl.glUniform1i(unisTrack.texTime,2)
      gl.glUniform1i(unisTrack.texHeatMap,3)
      gl.glUseProgram(0)
      
      progBasic = glu.loadprogram({
          GL_VERTEX_SHADER = "shaders/basic.vert.glsl",
          GL_FRAGMENT_SHADER = "shaders/basic.frag.glsl",
        })
      assert(progBasic, "could not load shaders/basic")
      
      unisBasic = glu.programuniforms(progBasic)
    end

    return context
  end
  
  local function bindMultiTexture( unit, what, tex)
    gl.glActiveTexture(unit)
    gl.glBindTexture(what,tex)
  end
  
  local function bufferData(buffer, ...)
    gl.glBindBuffer(gl.GL_TEXTURE_BUFFER, buffer)
    gl.glBufferData(gl.GL_TEXTURE_BUFFER, ...)
    gl.glBindBuffer(gl.GL_TEXTURE_BUFFER, 0)
  end
  
  local function bufferSubData(buffer, ...)
    gl.glBindBuffer(gl.GL_TEXTURE_BUFFER, buffer)
    gl.glBufferSubData(gl.GL_TEXTURE_BUFFER, ...)
    gl.glBindBuffer(gl.GL_TEXTURE_BUFFER, 0)
  end
  
  local function textureBuffer(tex, ...)
    gl.glBindTexture(gl.GL_TEXTURE_BUFFER, tex)
    gl.glTexBuffer  (gl.GL_TEXTURE_BUFFER, ...)
    gl.glBindTexture(gl.GL_TEXTURE_BUFFER, 0)
  end
  
  local function appendUpdate(trace)
    if (gfx.avg) then return end
    
    for i,v in ipairs(trace.lapData) do
      if (v.valid) then
        local samples = helpers.getNumSamples(trace, i)
        local pos     = ffi.new("float[?]", samples*4)
        local times   = ffi.new("float[?]", samples)
        helpers.getSampledData(trace, i, samples, {}, pos)
        
        bufferData(bufavg, 4*4*samples, pos, gl.GL_STATIC_DRAW)
        
        gfx.avg = {
          samples = samples,
          pos     = pos,
          times   = times,
          bufpos  = bufavg,
        }
        break
      end
    end
  end
  
  local function openUpdate(trace)
    -- find first valid lap
    gfx.avg      = nil
    gfx.trace    = trace
    appendUpdate(trace)
  end
  sys.registerHandler(sys.events.open, openUpdate)
  sys.registerHandler(sys.events.append, appendUpdate)
  
  local function clearRange(plot)
    plot.rangeBegin = nil
    plot.rangeEnd   = nil
    plot.rangeTimeBegin = nil
    plot.rangeTimeDuration = nil
  end
  
  local function updateRange(plot)
    if (gfx.rangeState == nil or not plot.pos) then 
      clearRange(plot)
      return
    end
    
    local function findClosest(begin, marker)
      local lastdist = 10000000000
      local idx = 0
      
      for i=begin,plot.samples-1 do
        local pos = plot.pos + i * 4
        local dist = v3.distance(pos,marker)
        if (dist < lastdist) then
          lastdist = dist
          idx  = i
        elseif (lastdist < 5) then
          return idx
        end
      end
      
      return idx
    end
    
    if (not plot.rangeBegin) then
      plot.rangeBegin = findClosest(0, gfx.rangeBegin)
      plot.rangeTimeBegin = plot.times[plot.rangeBegin]
      plot.rangeTimeDuration  = plot.times[plot.samples-1] - plot.rangeTimeBegin
    end
    if(gfx.rangeState == "end") then
      plot.rangeEnd   = findClosest(plot.rangeBegin, gfx.rangeEnd)
      plot.rangeTimeDuration  = plot.times[plot.rangeEnd] - plot.rangeTimeBegin
    end
  end
  
  local function rangeUpdate(rangeState)
    gfx.rangeState = rangeState
    if (rangeState == nil) then
      -- clear
      gfx.rangeBegin = nil
      gfx.rangeEnd   = nil
    elseif (rangeState == "begin") then
      -- begin
      gfx.rangeBegin = gfx.pos
    else
      -- end
      gfx.rangeEnd   = gfx.pos
    end
    for i=1,constants.MAX_PLOTS do
      updateRange(gfx.plots[i])
    end
  end
  
  sys.registerHandler(sys.events.range, rangeUpdate)
  
  local function setupBuffers(plot)
    bufferData    ( plot.bufpos, 4*4*plot.samples, plot.pos, gl.GL_STATIC_DRAW)
    textureBuffer ( plot.texpos, gl.GL_RGBA32F, plot.bufpos)

    bufferData    ( plot.buftimes, 4*plot.samples, plot.times, gl.GL_STATIC_DRAW)
    textureBuffer ( plot.textimes, gl.GL_R32F, plot.buftimes )
    
    bufferData    ( plot.bufdata, 4*plot.samples, plot.data, gl.GL_STATIC_DRAW)
    textureBuffer ( plot.texdata,  gl.GL_R32F, plot.bufdata )
  end

  local function lapUpdate(trace, lap)
    local plot = gfx.plot
    local samples = helpers.getNumSamples(trace, lap)
    
    -- create and fill new buffers
    plot.trace   = trace
    plot.samples = samples
    plot.lap     = lap
    plot.minmax  = nil
    plot.prop    = nil
    plot.selected = nil
    plot.gradient = nil
    plot.hasGradient = true
    plot.info    = " Lap "..lap.." Driving line - "..helpers.getTraceShortName(trace)
    
    plot.data  = ffi.new("float[?]", samples, 0)
    plot.pos   = ffi.new("float[?]", samples * 4)
    plot.times = ffi.new("float[?]", samples)
    
    -- keep original arrays around, as data above might be altered
    -- by comparisons
    plot.origsamples = samples
    plot.origpos  = plot.pos
    plot.origdata = plot.data
    plot.origtimes = plot.times
    
    helpers.getSampledData(trace, lap, samples, plot.times, plot.pos)
    
    setupBuffers(plot)
    
    clearRange(plot)
    updateRange(plot)
  end
  sys.registerHandler(sys.events.lap, lapUpdate)
  
  local function timeUpdate(trace, lap, time, state)
    gfx.pos = v3.float(state.Player.Position.X,state.Player.Position.Z,state.Player.Position.Y)
  end
  sys.registerHandler(sys.events.time, timeUpdate)

  local function propertyUpdate(trace, lap, selected, gradient)
    local plot = gfx.plot
    
    if (helpers.getNumSelected(selected)==0) then
      return
    end
    
    if (plot.trace ~= trace or plot.lap ~= lap or plot.compare) then
      lapUpdate(trace,lap)
    end
    
    -- reset original arrays, if previous was comparison
    plot.samples = plot.origsamples
    plot.pos     = plot.origpos
    plot.data    = plot.origdata
    plot.times   = plot.origtimes
    
    local samples = plot.samples
    local minmax = helpers.getSampledData(trace, lap, samples, nil, nil, gradient, selected, {plot.data})
    
    plot.selected = selected
    plot.prop   = selected.props[1]
    plot.minmax = minmax[1]
    plot.gradient = gradient
    plot.hasGradient = gradient > 0
    plot.compare = false
    
    bufferSubData(plot.bufdata, 0, 4*samples, plot.data)
    
    local info = plot.prop.name..string.format(" [ %.2f, %.2f ] ", plot.minmax[1],plot.minmax[2])..(gradient > 0 and " Gradient: "..gradient.." " or "")
    
    plot.info = " Lap "..plot.lap.." "..info.." - "..helpers.getTraceShortName(plot.trace)
  end
  
  sys.registerHandler(sys.events.property, propertyUpdate)
  
  local function propertyCompare(trace, lap, gradient)
    local plot = gfx.plot
    
    if (not gfx.avg or (plot.trace == trace and plot.lap == lap)) then return end
    
    -- sample
    local samples = helpers.getNumSamples(trace, lap)
    local rate    = trace.lapData[lap].time/(samples-1)
    local cmp = {
      samples = samples,
      pos     = ffi.new("float[?]", samples*4),
      times   = ffi.new("float[?]", samples),
      data    = ffi.new("float[?]", samples,    0)
    }
    
    helpers.getSampledData(trace, lap, samples, cmp.times, cmp.pos, plot.gradient, plot.selected, plot.selected and {cmp.data})
    
    local interpolate = not plot.prop or plot.prop.interpolate 
    -- use original data
    local plotdata = not plot.prop and plot.origtimes or plot.origdata
    local cmpdata  = not plot.prop and cmp.times      or cmp.data
    
    local newdata = ffi.new("float[?]", samples)
    
    local plotmarker = 1
    local cmpmarker  = 1
    
    local tangent = v3.float(0,0,0)
    local probe   = v3.float(0,0,0)
    local minmax = {100000000,-100000000}
    
    newdata[0] = cmpdata[0] - plotdata[0]
    for i=1, samples-2 do
      refpos  = cmp.pos + (i*4)
      refprev = refpos - 4
      refnext = refpos + 4
      
      v3.sub(tangent, refnext, refprev)
      
      -- advance until sampled is in front of reference
      -- merge previous and front based on distance
      local function computeSample(marker, samples, trackpos, trackdata)
        
        while true do
          local pos = trackpos + (marker * 4)
          v3.sub(probe, pos, refpos)
          
          if (v3.dot(probe,tangent) > 0 or marker == samples-1) then
            local wtA = v3.distance(pos - 4, refpos)
            local wtB = v3.length(probe)
            local data
            if (interpolate) then
              local sum = wtA + wtB
              -- apply weight of opposite
              data = (trackdata[marker]*wtA + trackdata[marker-1]*wtB) / sum
            else
              data = wtA < wtB and trackdata[marker] or trackdata[marker-1]
            end
            
            return marker, data
          end
          
          marker = marker + 1
        end
      end
      
      local cmpvalue
      local plotvalue
      --cmpmarker,  cmpvalue  = computeSample(cmpmarker,  cmp.samples,  cmp.pos,  cmpdata)
      local cmpvalue = cmpdata[i]
      plotmarker, plotvalue = computeSample(plotmarker, plot.origsamples, plot.origpos, plotdata)
      
      local value = cmpvalue - plotvalue
      newdata[i] = value
      minmax[1] = math.min(minmax[1], value)
      minmax[2] = math.max(minmax[2], value)
    end
    newdata[samples-1] = cmpdata[cmp.samples-1] - plotdata[plot.origsamples-1]
    
    if (gradient > 0) then
      local data = ffi.new("float[?]",samples)
      minmax = {100000000,-100000000}
      
      local gradstep = math.ceil((gradient/100)*0.5/rate)
      
      for i=0,samples-1 do
        local value = newdata[ math.min(samples-1, i + gradstep)] - newdata[ math.max(0,i - gradstep)]
        minmax[1] = math.min(minmax[1], value)
        minmax[2] = math.max(minmax[2], value)
        data[i] = value
      end
      newdata = data
    end
    
    plot.minmax = minmax
    plot.samples = samples
    plot.times = cmp.times
    plot.pos   = cmp.pos
    plot.data  = newdata
    
    local name = not plot.prop and "Time" or plot.prop.name
    local info = name..((plot.gradient or 0) > 0 and ".gradient("..plot.gradient..") " or "")..string.format(" [ %.2f, %.2f ] ", plot.minmax[1],plot.minmax[2])..(gradient > 0 and " Gradient: "..gradient.." " or "")
    
    plot.info = " Lap "..lap.."/"..plot.lap.." "..info.." - "..helpers.getTraceShortName(trace).."/"..helpers.getTraceShortName(plot.trace)
    plot.compare = true
    
    setupBuffers(plot)
    
    clearRange(plot)
    updateRange(plot)
  end
  
  sys.registerHandler(sys.events.compare, propertyCompare)
  
  function gfx.drawTrack(w,h,zoom,pan)
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
    gl.glEnable(gl.GL_SAMPLE_ALPHA_TO_COVERAGE)
    
    local viewProjTM = m4.float() 
    m4.mulA( viewProjTM, m4.scaled( m4.tab(), zoom, zoom, 1 ))
    m4.mulA( viewProjTM, m4.translated( m4.tab(), pan[1], pan[2], 0))
    m4.mulA( viewProjTM, m4.ortho( m4.tab(), -1*aspectw,1*aspectw, -1*aspecth, 1*aspecth, -1, 1))
    
    local scale = math.max(hrange[1],hrange[2])
    if (rotate) then
      m4.mulA( viewProjTM, m4.rotatedXYZ( m4.tab(), v3.tab(0,0,math.rad(-90)) ))
    end
    m4.mulA( viewProjTM, m4.scaled( m4.tab(), 1/scale, 1/scale, 1/scale ))
    m4.mulA( viewProjTM, m4.translated( m4.tab(),
                    -gfx.trace.posMin[1]-hrange[1],
                    -gfx.trace.posMin[3]-hrange[2],
                    -gfx.trace.posMin[2]-hrange[3]))
    
    local numPlots = 0
    local numRacelines = 0
    local numData = 0
    local plots = {}
    
    local minRangeDuration = 1000000
    
    -- racelines first
    for i=1,constants.MAX_PLOTS do
      if (gfx.enabled[i] and gfx.plots[i].trace and gfx.plots[i].minmax == nil) then 
        plots[numPlots+1] = gfx.plots[i]
        numRacelines = numRacelines + 1
        numPlots = numPlots + 1
        
        minRangeDuration = math.min(minRangeDuration, gfx.plots[i].rangeTimeDuration or minRangeDuration)
      end
    end
    for i=1,constants.MAX_PLOTS do
      if (gfx.enabled[i] and gfx.plots[i].trace and gfx.plots[i].minmax ) then 
        plots[numPlots+1] = gfx.plots[i]
        numData  = numData + 1
        numPlots = numPlots + 1
        
        minRangeDuration = math.min(minRangeDuration, gfx.plots[i].rangeTimeDuration or minRangeDuration)
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
        local function checkMatch(what)
          return (a.prop.name:match(what) ~= nil) and (b.prop.name:match(what) ~= nil)
        end
        
        if (a.minmax and b.minmax and 
            a.prop and b.prop and
            a.gradient == b.gradient and
          ( a.prop.name == b.prop.name  or
            checkMatch("Temp") or 
            checkMatch("Pressure") or 
            checkMatch("Time") or 
            checkMatch("Pedal")
          ))
        then
          local merged = {math.min(a.minmax[1],b.minmax[1]), math.max(a.minmax[2],b.minmax[2])}
          minmaxs[i] = merged
          minmaxs[n] = merged
        end
      end
    end
    
    local curData     = 0
    local curRaceline = 0
    for i=1,numPlots do
      local plot = plots[i]
    
      local isline = plot.minmax == nil
      
      local dataTM = m4.float()
      do
        local minmax = minmaxs[i] or {-1,1}
        local negative = minmax[1] < -0.0001
        local range = math.max(minmax[2],math.abs(minmax[1]))
        local simple = minmax[1] > -0.0001 and minmax[2] < 1.0001
        if (plot.hasGradient or negative or simple) then
          -- [-range,range]
          m4.mulA( dataTM, m4.scaled( m4.tab(), 1/(range*2),1,1 ))
          m4.mulA( dataTM, m4.translated( m4.tab(), range,0,0 ) )
        else
          -- [0,range]
          m4.mulA( dataTM, m4.scaled( m4.tab(), 1/range,1,1 ))
        end
        if (isline ) then
          local offset = numRacelines > 1 and ((curRaceline)/(numRacelines-1))*1.5-0.75 or -0.5
          m4.mulA( dataTM, m4.translated( m4.tab(), offset,0,0 ) )
        end
      end
      
      gl.glUseProgram(progTrack)
      
      bindMultiTexture(gl.GL_TEXTURE0, gl.GL_TEXTURE_BUFFER, plot.texpos)
      bindMultiTexture(gl.GL_TEXTURE1, gl.GL_TEXTURE_BUFFER, plot.texdata)
      bindMultiTexture(gl.GL_TEXTURE2, gl.GL_TEXTURE_BUFFER, plot.textimes)
      bindMultiTexture(gl.GL_TEXTURE3, gl.GL_TEXTURE_1D, texheat)
      
      gl.glUniformMatrix4fv( unisTrack.viewProjTM, 1, gl.GL_FALSE, viewProjTM )
      gl.glUniformMatrix4fv( unisTrack.dataTM, 1, gl.GL_FALSE, dataTM)
      
      if (isline) then
        gl.glUniform1f(unisTrack.shift, 0)
        gl.glUniform1f(unisTrack.width, (numData > 0 and numRacelines == 1 and 8 or 6) * gfx.widthmul)
        gl.glUniform4f(unisTrack.color, 0.55,0.55,0.55, numData > 0 and numRacelines == 1 and 1 or 0)
      else
        local width     =(numData > 2 and 4 or 6) * gfx.widthmul
        local shift     = numData > 1 and width*2.1 or 0
        local shiftbase = numData > 1 and -((numData-1)*shift + width*2)*0.5+width or 0
        gl.glUniform1f(unisTrack.shift, shift * (curData) + shiftbase)
        gl.glUniform1f(unisTrack.width, width)
        gl.glUniform4f(unisTrack.color, 1,1,1,0)
      end
      
      if (isline) then
        local width = 0.7 --1/numRacelines
        local start = i*0.5 - (os.clock()*2 % 1)
        gl.glUniform4f(unisTrack.timestipple, 1, start, width, 1)
      else
        gl.glUniform4f(unisTrack.timestipple, 1,1,1,0)
      end
      
      gl.glUniform2f(unisTrack.sidecontrol, numData > 2 and 1/(numData-2) or 0.75, 
                                            numData > 1 and 1/(numData-1) or 0)
      
      local timeBegin = plot.rangeTimeBegin or -1
      gl.glUniform2f(unisTrack.timeclamp, -1, timeBegin + minRangeDuration)
      
      local numPoints = plot.samples
      gl.glUniform1i(unisTrack.numPoints, plot.samples)
      
      local vertexBegin     = plot.rangeBegin and plot.rangeBegin*2 or 0
      local vertexEnd       = plot.rangeEnd   and plot.rangeEnd*2   or numPoints*2
      local numVertices     = vertexEnd - vertexBegin
      
      gl.glDrawArrays(gl.GL_TRIANGLE_STRIP, vertexBegin, numVertices)
      
      gl.glDisableVertexAttribArray(0)
      gl.glDisableVertexAttribArray(1)
      
      bindMultiTexture(gl.GL_TEXTURE3, gl.GL_TEXTURE_1D, 0)
      bindMultiTexture(gl.GL_TEXTURE2, gl.GL_TEXTURE_BUFFER, 0)
      bindMultiTexture(gl.GL_TEXTURE1, gl.GL_TEXTURE_BUFFER, 0)
      bindMultiTexture(gl.GL_TEXTURE0, gl.GL_TEXTURE_BUFFER, 0)
      
      if (isline) then
        curRaceline = curRaceline + 1
      else
        curData = curData + 1
      end
    end
    
    if (gfx.avg) then
      
      local samples = gfx.avg.samples
      local buffer  = gfx.avg.bufpos
      
      gl.glUseProgram(progBasic)
      gl.glUniformMatrix4fv( unisBasic.viewProjTM, 1, gl.GL_FALSE, viewProjTM)
      
      --gl.glLineStipple(1, 0x5555)
      --gl.glLineStipple(1, 0x0F0F)
      gl.glLineStipple(1, 0x00FF)
      gl.glEnable(gl.GL_LINE_STIPPLE)
      
      gl.glBindBuffer(gl.GL_ARRAY_BUFFER, buffer)
      gl.glVertexAttribPointer(0, 4, gl.GL_FLOAT, gl.GL_FALSE, 4*4, nil)
      gl.glEnableVertexAttribArray(0)
      
      gl.glLineWidth(2)
      gl.glUniform4f(unisBasic.color, 1, 1, 1, 1)
      gl.glDrawArrays(gl.GL_LINE_STRIP, 0, samples)
      
      gl.glLineWidth(1.5)
      gl.glUniform4f(unisBasic.color, 0.2, 0.2, 0.2,1)
      gl.glDrawArrays(gl.GL_LINE_STRIP, 0, samples)
      
      gl.glDisableVertexAttribArray(0)
      gl.glDisable(gl.GL_LINE_STIPPLE)
      
      gl.glEnable(gl.GL_POINT_SMOOTH)
      gl.glUniform4f(unisBasic.color, 0,0,0,1)
      gl.glPointSize(16)
      gl.glBegin(gl.GL_POINTS)
      gl.glVertexAttrib3f(0, gfx.pos[0], gfx.pos[1], gfx.pos[2])
      gl.glEnd()
      gl.glDisable(gl.GL_POINT_SMOOTH)
    end
  end
end

return gfx