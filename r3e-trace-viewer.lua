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

---------------------------------------------

local function getSampledData(trace, lap, selected, gradient)
  local state = ffi.new( r3e.SHARED_TYPE )
  local statePrev = ffi.new( r3e.SHARED_TYPE )
  local stateNext = ffi.new( r3e.SHARED_TYPE )
  
  local samplerate = config.samplerate or 0.1
  local lap = trace.lapData[lap]
  
  local timeBegin = lap.timeBegin
  local timeEnd   = lap.timeBegin + lap.time
  
  local times   = {}
  local outputs = {}
  local num     = #selected.props
  for i=1,num do
    outputs[i] = {}
  end
  
  local function getMagnitude(res)
    return math.sqrt(res[1]*res[1] + res[2]*res[2] + res[3]*res[3])
  end
  
  local results = {}
  local resultsPrev = {}
  local resultsNext = {}
  local time,n = timeBegin,0
  while time < timeEnd do
    local laptime = time-timeBegin
    table.insert(times, laptime)
    
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
      end
    else
      trace:getInterpolatedFrame(state, time)
      selected.fnaccess(results, state)
      for i=1,num do
        local v = selected.props[i]
        local res = results[i]
        if (v.descr == "r3e_vec3_f64" or v.descr == "r3e_vec3_f32") then
          res = getMagnitude(res)
        end
        table.insert(outputs[i], res)
      end
    end
    
    n = n + 1
    time = lap.timeBegin + samplerate * n
  end
  
  return times, num, outputs, n
end

local function saveCSV(trace, lap, selected, gradient, filename)
  local times, num, outputs, samples = getSampledData(trace, lap, selected, gradient)
  
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
local traceFileName = args[2]
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
                            wx.wxDefaultPosition, wx.wxSize(360, 200),
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
  
  local panel = wx.wxPanel( propSplitter, wx.wxID_ANY)
  
  lapSplitter:SplitVertically(lap,propSplitter)
  propSplitter:SplitVertically(props,panel)
  
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

  tools:Connect(ID_SPNGRAD, wx.wxEVT_COMMAND_SPINCTRL_UPDATED,
    function (event)
      
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

if (false) then
  local init = true

  local canvas = wx.wxGLCanvas(frame, wx.wxID_ANY, {
  wx.WX_GL_RGBA, 1, wx.WX_GL_DOUBLEBUFFER, 1, 
  wx.WX_GL_MIN_RED, 8, wx.WX_GL_MIN_GREEN, 8, wx.WX_GL_MIN_BLUE, 8, wx.WX_GL_MIN_ALPHA, 8,
  wx.WX_GL_STENCIL_SIZE, 8, wx.WX_GL_DEPTH_SIZE, 24
  },
  wx.wxDefaultPosition, wx.wxDefaultSize, wx.wxEXPAND)
  local context = wx.wxGLContext(canvas)
  local function render()
    context:SetCurrent(canvas)
    
    if (init) then
      gl.glewInit()
      init = false
    end

    gl.glClearColor(1, 1, 1, 1)
    gl.glClear(0xFFFFFFFF)

    gl.glColor3f(math.random(),math.random(),math.random())
    local offset = math.random()*0.1
    gl.glBegin(gl.GL_TRIANGLES)
      gl.glVertex3f( 0,  0.75 + offset, 0)
      gl.glVertex3f(-0.75+ offset, -0.75+ offset, 0)
      gl.glVertex3f( 0.75+ offset, -0.75+ offset, 0)
    gl.glEnd()

    canvas:SwapBuffers()
  end
  canvas:Connect(wx.wxEVT_PAINT, render)
end

app = initApp()

traceSetFile(traceFileName)

-- show the frame window
app:Show(true)
wx.wxGetApp():MainLoop()