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
local ID_SPINNER  = NewID()
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
                            wx.wxLC_REPORT)
  
  frame:Connect(ID_LAP, wx.wxEVT_COMMAND_LIST_ITEM_ACTIVATED,
  function (event)
    if (not trace) then return end
    
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
      control:InsertItem(i-1, v.valid and tostring(i) or "("..tostring(i)..")")
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
    control:InsertItem(i-1, v[1])
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
  
  local tools = wx.wxPanel( frame, wx.wxID_ANY)
  frame.tool = tools
  
  local slider  = wx.wxSlider(tools, ID_SLIDER, 0, 0, SLIDER_RES)
  local spinner = wx.wxTextCtrl(tools, ID_SPINNER, "0", wx.wxDefaultPosition, wx.wxDefaultSize, wx.wxTE_READONLY)
  frame.slider  = slider
  frame.spinner = spinner
  local sizer = wx.wxBoxSizer(wx.wxHORIZONTAL)
  sizer:Add(spinner, 0, wx.wxEXPAND)
  sizer:Add(slider, 1, wx.wxEXPAND)
  tools:SetSizer(sizer)
  
  local function lap()
    -- reset
    slider:SetValue(0)
    spinner:ChangeValue("0")
  end
  registerHandler(events.lap, lap)
  
  tools:Connect(ID_SLIDER, wx.wxEVT_COMMAND_SLIDER_UPDATED,
  function (event)
    if (not traceLapData) then return end
    
    local fracc = event:GetInt()/(SLIDER_RES-1)
    local laptime = traceLapData.time * fracc
    local time = traceLapData.timeBegin + laptime
    
    traceSetTime(time)
    spinner:ChangeValue(toMS(laptime))
  end)
    
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