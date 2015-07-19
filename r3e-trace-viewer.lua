local wx = require "wx"
local ffi = require "ffi"
local gl  = require "glewgl"
local utils = require "utils"
local r3e = require "r3e"
local r3etrace = require "r3etrace"
local r3emap   = require "r3emap"

local config       = {record={}, replay={}, viewer={}}
CONFIG = config

utils.loadInto("config.lua", config)
utils.loadInto("config-user.lua", config)

local args = _ARGS or {...}
local APP_NAME  = "R3E Trace Viewer"
local SLIDER_RES = 2048
local AVG_RES    = 2048
---------------------------------------------

local function getSampledData(trace, lap, selected, gradient, fixednum)
  local state = ffi.new( r3e.SHARED_TYPE )
  local statePrev = ffi.new( r3e.SHARED_TYPE )
  local stateNext = ffi.new( r3e.SHARED_TYPE )
  
  local samplerate = config.samplerate or 0.1
  local lap = trace.lapData[lap]
  
  local timeBegin = lap.timeBegin
  local timeEnd   = lap.timeBegin + lap.time
  local rate = fixednum and lap.time/fixednum or samplerate
  
  local pos     = {}
  local times   = {}
  local outputs = {}
  local minmax  = {}
  local num     = selected and #selected.props or 0
  for i=1,num do
    outputs[i] = {}
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
  local time,n = timeBegin,0
  
  while time < timeEnd do
    trace:getInterpolatedFrame(state, time)
    
    local laptime = time-timeBegin
    table.insert(times, laptime)
    -- swizzle pos
    table.insert(pos, state.Player.Position.X)
    table.insert(pos, state.Player.Position.Z)
    table.insert(pos, state.Player.Position.Y)
    
    if (num > 0) then
      if (gradient > 0) then
        trace:getInterpolatedFrame(statePrev, time - gradient * samplerate)
        trace:getInterpolatedFrame(stateNext, time + gradient * samplerate)
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
          table.insert(outputs[i], res)
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
          table.insert(outputs[i], res)
          checkMinMax(i,res)
        end
      end
    end
  
    n = n + 1
    time = lap.timeBegin + rate * n
  end
  
  return n, times, pos, num, outputs, minmax 
end

local function saveCSV(trace, lap, selected, gradient, filename)
  local samples, times, pos, num, outputs, minmax = getSampledData(trace, lap, selected, gradient)
  
  local f = io.open(filename,"wt")
  f:write('"times"; ')
  for i=1,num do
    f:write('"'..selected.props[i].name..'"; ')
  end
  f:write("\n")
  for n=1,samples do
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
  
  frame:Connect(ID_LAP, wx.wxEVT_COMMAND_LIST_ITEM_ACTIVATED,
  function (event)
    if (not trace) then return end
    control:SetItem(traceLap-1, 0, lapString(traceLap,false))
    control:SetItem(event:GetIndex(), 0, lapString(event:GetIndex()+1,true))
    traceSetLap( event:GetIndex()+1)
  end)

  local handlers = {}
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
  
  function control.getSelected()
    local result = {
      props = {},
      fnaccess = nil,
    }
    -- built prop table
    for i,v in ipairs(props) do
      if (control:GetItemState(i-1, wx.wxLIST_STATE_SELECTED) ~= 0) then
        table.insert(result.props, v)
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
  trace   = nil,
  lap     = 0,
  samples = 0,
  samplesAvg = nil,
  gradient = true,
  minmax = nil,
}
do
  local glcontext -- the primary context
  local texheat = ffi.new("GLuint[1]")
  local buftime = ffi.new("GLuint[1]")
  local bufpos  = ffi.new("GLuint[1]")
  local bufavg  = ffi.new("GLuint[1]")
  local bufdata = ffi.new("GLuint[1]")
  
  function gfx.createSharedContext(canvas)
    local context 
    if (glcontext) then
      context = wx.wxGLContext(canvas, glcontext)
      
    else
      context = wx.wxGLContext(canvas)
      glcontext = context
      context:SetCurrent(canvas)
      gl.glewInit()
      
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
      gl.glBindTexture (gl.GL_TEXTURE_1D, texheat[0])
      gl.glTexImage1D  (gl.GL_TEXTURE_1D, 0, gl.GL_RGB16F, #heatmap/3, 0,
        gl.GL_RGB, gl.GL_FLOAT, ffi.cast("GLubyte*",heatdata))
      gl.glTexParameteri(gl.GL_TEXTURE_1D, gl.GL_TEXTURE_MIN_FILTER, gl.GL_LINEAR)
      gl.glTexParameteri(gl.GL_TEXTURE_1D, gl.GL_TEXTURE_MAG_FILTER, gl.GL_LINEAR)
      gl.glTexParameteri(gl.GL_TEXTURE_1D, gl.GL_TEXTURE_WRAP_S, gl.GL_CLAMP_TO_EDGE)
      gl.glBindTexture (gl.GL_TEXTURE_1D, 0)
      
      
      gl.glGenBuffers(1,buftime)
      gl.glGenBuffers(1,bufpos)
      gl.glGenBuffers(1,bufdata)
      gl.glGenBuffers(1,bufavg)
    end
    return context
  end
  
  function gfx.openUpdate(trace)
    -- find first valid lap
    gfx.samplesAvg = nil
    for i,v in ipairs(trace.lapData) do
      if (v.valid) then
        local samples, times, pos = getSampledData(trace, i, nil, nil, AVG_RES)
        local raw  = ffi.new("float[?]", samples*3,   pos)
        gl.glBindBuffer(gl.GL_ARRAY_BUFFER, bufavg[0])
        gl.glBufferData(gl.GL_ARRAY_BUFFER, ffi.sizeof("float")*3*samples, raw, gl.GL_STATIC_DRAW)
        gfx.samplesAvg = samples
        break
      end
    end
    
  end
  registerHandler(events.open, gfx.openUpdate)

  function gfx.lapUpdate(trace, lap)
    -- create and fill new buffers
    local samples, times, pos = getSampledData(trace, lap)
    gfx.trace   = trace
    gfx.samples = samples
    gfx.lap     = lap
    gfx.minmax  = {-1,1}
    gfx.gradient= true
    
    local raw  = ffi.new("float[?]", samples*3,   pos)
    gl.glBindBuffer(gl.GL_ARRAY_BUFFER, bufpos[0])
    gl.glBufferData(gl.GL_ARRAY_BUFFER, ffi.sizeof("float")*3*samples, raw, gl.GL_STATIC_DRAW)
    
    local raw = ffi.new("float[?]", samples, times)
    gl.glBindBuffer(gl.GL_ARRAY_BUFFER, buftime[0])
    gl.glBufferData(gl.GL_ARRAY_BUFFER, ffi.sizeof("float")*samples, raw, gl.GL_STATIC_DRAW)
    
    local raw  = ffi.new("float[?]", samples, 0)
    gl.glBindBuffer(gl.GL_ARRAY_BUFFER, bufdata[0])
    gl.glBufferData(gl.GL_ARRAY_BUFFER, ffi.sizeof("float")*samples, raw, gl.GL_STATIC_DRAW)
    
    gl.glBindBuffer(gl.GL_ARRAY_BUFFER, 0)
  end
  registerHandler(events.lap, gfx.lapUpdate)
  
  function gfx.timeUpdate(trace, lap, time, state)
    gfx.pos = {state.Player.Position.X,state.Player.Position.Z,state.Player.Position.Y}
  end
  registerHandler(events.time, gfx.timeUpdate)

  function gfx.propertyUpdate(trace, lap, selected, gradient)
    if (not selected or #selected.props == 0) then
      return
    end
    
    local samples, times, pos, n, outputs, minmax = getSampledData(trace, lap, selected, gradient)
    samples = math.min(gfx.samples,samples)
    outputs = outputs[1]
    minmax = minmax[1]
    
    gfx.minmax = minmax
    gfx.gradient = gradient > 0
    
    local dataraw  = ffi.new("float[?]", samples, outputs)
    gl.glBindBuffer(gl.GL_ARRAY_BUFFER, bufdata[0])
    gl.glBufferSubData(gl.GL_ARRAY_BUFFER, 0, ffi.sizeof("float")*samples, dataraw)
    gl.glBindBuffer(gl.GL_ARRAY_BUFFER, 0)
    
    local res = selected.props[1].name..string.format(" [ %.2f, %2.f ] ", minmax[1],minmax[2])..(gradient > 0 and " Gradient: "..gradient.." " or "")
    return res
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
    
    -- uh writing fixed function GL makes me feel at least 10 years younger
    gl.glMatrixMode(gl.GL_PROJECTION)
    gl.glLoadIdentity()
    gl.glOrtho(-1*aspectw,1*aspectw, -1*aspecth, 1*aspecth, -1, 1)
    
    gl.glColor4f(1,1,1,1)
    
    gl.glMatrixMode(gl.GL_MODELVIEW)
    gl.glLoadIdentity()
    local scale = math.max(hrange[1],hrange[2])
    if (rotate) then
      gl.glRotatef(-90,0,0,1)
    end
    gl.glScalef(1/scale, 1/scale, 1/scale)
    -- subtract min+range/2
    gl.glTranslatef(-gfx.trace.posMin[1]-hrange[1],
                    -gfx.trace.posMin[3]-hrange[2],
                    -gfx.trace.posMin[2]-hrange[3])
    
    gl.glBindBuffer(gl.GL_ARRAY_BUFFER, bufpos[0])
    gl.glVertexPointer(3, gl.GL_FLOAT, 4*3*stride, nil)
    gl.glEnableClientState(gl.GL_VERTEX_ARRAY)
    
    gl.glBindTexture(gl.GL_TEXTURE_1D, texheat[0])
    gl.glEnable(gl.GL_TEXTURE_1D)
    gl.glBindBuffer(gl.GL_ARRAY_BUFFER, bufdata[0])
    gl.glTexCoordPointer(1, gl.GL_FLOAT, 4*stride, nil)
    gl.glEnableClientState(gl.GL_TEXTURE_COORD_ARRAY)
    gl.glMatrixMode(gl.GL_TEXTURE)
    gl.glLoadIdentity()
    
    local range = math.max(gfx.minmax[2],math.abs(gfx.minmax[1]))
    if (gfx.gradient) then
      -- [-range,range]
      gl.glScalef(1/(range*2),1,1)
      gl.glTranslatef(range,0,0)
    else
      -- [0,rage]
      gl.glScalef(1/range,1,1)
    end
    
    local width = 8
    gl.glLineWidth(width)
    gl.glEnable(gl.GL_BLEND)
    gl.glEnable(gl.GL_POINT_SMOOTH)
    gl.glEnable(gl.GL_LINE_SMOOTH)
    gl.glPointSize(width)
    
    gl.glDrawArrays(gl.GL_POINTS, 0, math.floor(gfx.samples/stride))
    gl.glDrawArrays(gl.GL_LINE_STRIP, 0, math.floor(gfx.samples/stride))
    
    gl.glDisableClientState(gl.GL_TEXTURE_COORD_ARRAY)
    gl.glDisable(gl.GL_TEXTURE_1D)
    
    if (gfx.samplesAvg) then
      local clr = 0.7
      gl.glColor4f(clr,clr,clr,0)
      gl.glLineWidth(1)
      gl.glBindBuffer(gl.GL_ARRAY_BUFFER, bufavg[0])
      gl.glVertexPointer(3, gl.GL_FLOAT, 4*3, nil)
      
      gl.glDrawArrays(gl.GL_LINE_STRIP, 0, gfx.samplesAvg)
      
      gl.glLineWidth(width)
    end
    gl.glDisableClientState(gl.GL_VERTEX_ARRAY)
    
    gl.glColor4f(0,0,0,1)
    gl.glBegin(gl.GL_POINTS)
    gl.glVertex3f(gfx.pos[1], gfx.pos[2], gfx.pos[3])
    gl.glEnd()
    
    gl.glDisable(gl.GL_BLEND)
    gl.glDisable(gl.GL_POINT_SMOOTH)
    gl.glDisable(gl.GL_LINE_SMOOTH)
  end
end
---------------------------------------------

local function initTrackView(frame)
  local init = true

  local canvas = wx.wxGLCanvas(frame, wx.wxID_ANY, {
  wx.WX_GL_RGBA, 1, wx.WX_GL_DOUBLEBUFFER, 1, 
  wx.WX_GL_MIN_RED, 8, wx.WX_GL_MIN_GREEN, 8, wx.WX_GL_MIN_BLUE, 8, wx.WX_GL_MIN_ALPHA, 8,
  wx.WX_GL_STENCIL_SIZE, 8, wx.WX_GL_DEPTH_SIZE, 24,
  wx.WX_GL_SAMPLE_BUFFERS, 1, wx.WX_GL_SAMPLES, 4
  },
  wx.wxDefaultPosition, wx.wxDefaultSize, wx.wxEXPAND + wx.wxFULL_REPAINT_ON_RESIZE)

  --local lbl = wx.wxTextCtrl(canvas, wx.wxID_ANY, "Blah",wx.wxDefaultPosition, wx.wxSize(78,24), wx.wxTE_READONLY)
  local lbl = wx.wxStaticText(canvas, wx.wxID_ANY, " No Data ")
  canvas.lbl = lbl

  local context = gfx.createSharedContext(canvas)
  
  local function render()
    
    context:SetCurrent(canvas)
    
    local sz = canvas:GetSize()
    local w,h = sz:GetWidth(), sz:GetHeight()
   
    gl.glViewport(0,0,w,h)

    gl.glClearDepth(1)
    gl.glClearStencil(0)
    gl.glClearColor(1, 1, 1, 1)
    gl.glClear(gl.GL_COLOR_BUFFER_BIT + gl.GL_DEPTH_BUFFER_BIT + gl.GL_STENCIL_BUFFER_BIT)
    
    if (gfx.minmax) then 
      gfx.drawTrack(w,h,zoom,pan)
    end

    canvas:SwapBuffers()
  end
  canvas:Connect(wx.wxEVT_PAINT, render)
  --canvas:Connect(wx.wxEVT_SIZE,  render)
  
  registerHandler(events.lap, function() lbl:SetLabel(" No Data ") end)
  registerHandler(events.time, function() canvas:Refresh() end)
  
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
  local lblgrad = wx.wxStaticText(toolsAction, wx.wxID_ANY, "Gradient Width:", wx.wxDefaultPosition, wx.wxSize(86,24), wx.wxALIGN_RIGHT)
  local spngrad = wx.wxSpinCtrl(toolsAction, ID_SPNGRAD, "", wx.wxDefaultPosition, wx.wxSize(50,24))
  
  frame.btnexport = btnexport
  frame.btnplot = btnplot
  frame.lbltime = lbltime
  frame.txttime = txttime
  frame.lblgrad = lblgrad
  frame.spngrad = spngrad
  frame.slider  = slider
  
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
  
  tools:Connect(ID_SLIDER, wx.wxEVT_COMMAND_SLIDER_UPDATED,
  function (event)
    if (not traceLapData) then return end
    
    local fracc = event:GetInt()/(SLIDER_RES-1)
    local laptime = traceLapData.time * fracc
    local time = traceLapData.timeBegin + laptime
    
    traceSetTime(time)
    txttime:ChangeValue(toMS(laptime))
  end)

  props:Connect(ID_PROPERTY, wx.wxEVT_COMMAND_LIST_ITEM_ACTIVATED,
    function (event)
      local res = gfx.propertyUpdate(trace, traceLap, props.getSelected(), spngrad:GetValue())
      if (res) then
        trackview.lbl:SetLabel(" Lap:"..traceLap.." "..res)
      end
      trackview:Refresh()
      
    end)

  tools:Connect(ID_BTNPLOT, wx.wxEVT_COMMAND_BUTTON_CLICKED,
    function (event)
      local res = gfx.propertyUpdate(trace, traceLap, props.getSelected(), spngrad:GetValue())
      if (res) then
        trackview.lbl:SetLabel(" Lap:"..traceLap.." "..res)
      end
      trackview:Refresh()
      
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