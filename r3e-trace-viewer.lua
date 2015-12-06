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
gCONFIG = config

utils.loadInto("config.lua", config)
utils.loadInto("config-user.lua", config)

r3emap  = r3emap.init(fulldata)
gR3EMAP = r3emap

local constants = {
  APP_NAME  = "R3E Trace Viewer",
  SLIDER_RES = 2048,
  MAX_PLOTS  = 4,
  SHARED_TYPE = config.viewer.fulldata and r3e.SHARED_TYPE_FULL or r3e.SHARED_TYPE,
}
gCONSTANTS = constants

local app
local function reportStatus(text)
  app:SetStatusText(text)
end
gAPP = {
  reportStatus = reportStatus,
}

local helpers = dofile("viewer/helpers.lua")
local toMS    = helpers.toMS

local sys     = dofile("viewer/system.lua")
local active  = sys.active
local events  = sys.events

local gfx     = dofile("viewer/gfx.lua")

local initLapView      = dofile("viewer/view_lap.lua")
local initPropertyView = dofile("viewer/view_property.lua")
local initTrackView    = dofile("viewer/view_track.lua")


---------------------------------------------
local function initApp()
  local NewID = sys.NewID
  
  local ID_MAIN = NewID()
  local frame = wx.wxFrame(wx.NULL, ID_MAIN, constants.APP_NAME,
  wx.wxDefaultPosition, wx.wxSize(1024, 768), wx.wxDEFAULT_FRAME_STYLE)

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


  local ID_TIMER = NewID()
  local timer = wx.wxTimer(frame, ID_TIMER)
  frame.timer = timer
  
  local ID_MENUAPPEND = NewID()
  local ID_MENUEXPORT = NewID()

  -- create a simple file menu
  local fileMenu = wx.wxMenu()
  fileMenu:Append(wx.wxID_OPEN, "&Open", "Open Trace file")
  fileMenu:Append(ID_MENUAPPEND,"&Append", "Append Trace file")
  fileMenu:Append(ID_MENUEXPORT,"&Save As", "Save session as csv file")
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
  
  local mgr = wxaui.wxAuiManager()
  frame.mgr = mgr
  
  local winManaged = wx.wxWindow(frame, wx.wxID_ANY, wx.wxDefaultPosition, wx.wxSize(1024, 768)) 
  frame.winManaged = winManaged
  mgr:SetManagedWindow(winManaged);

  
  local settings = wx.wxFileConfig("RaceTraceViewer", "CKRaceTools", "")

  local function settingsReadSafe(settings,what,default)
    local cr,out = settings:Read(what,default)
    return cr and out or default
  end

  local function settingsRestoreFramePosition(window, windowName)
    local path = settings:GetPath()
    settings:SetPath("/"..windowName)

    local s = -1
    s = tonumber(select(2,settings:Read("s", -1)))
    local x = tonumber(select(2,settings:Read("x", 0)))
    local y = tonumber(select(2,settings:Read("y", 0)))
    local w = tonumber(select(2,settings:Read("w", 1000)))
    local h = tonumber(select(2,settings:Read("h", 700)))

    if (s ~= -1) and (s ~= 1) and (s ~= 2) then
      local clientX, clientY, clientWidth, clientHeight
      clientX, clientY, clientWidth, clientHeight = wx.wxClientDisplayRect()

      if x < clientX then x = clientX end
      if y < clientY then y = clientY end

      if w > clientWidth then w = clientWidth end
      if h > clientHeight then h = clientHeight end

      window:SetSize(x, y, w, h)
    elseif s == 1 then
      window:Maximize(true)
    end

    settings:SetPath(path)
  end

  local function settingsSaveFramePosition(window, windowName)
    local path = settings:GetPath()
    settings:SetPath("/"..windowName)

    local s = 0
    local w, h = window:GetSizeWH()
    local x, y = window:GetPositionXY()

    if window:IsMaximized() then
      s = 1
    elseif window:IsIconized() then
      s = 2
    end

    settings:Write("s", s==2 and 0 or s) -- iconized maybe - but that shouldnt be saved

    if s == 0 then
      settings:Write("x", x)
      settings:Write("y", y)
      settings:Write("w", w)
      settings:Write("h", h)
    end

    settings:SetPath(path)
  end
  
  frame:Connect(wx.wxEVT_DESTROY,
    function(event)
      if (event:GetEventObject():DynamicCast("wxObject") == frame:DynamicCast("wxObject")) then
        -- You must ALWAYS UnInit() the wxAuiManager when closing
        -- since it pushes event handlers into the frame.
        mgr:UnInit()
      end 
    end)
  
  frame:Connect(wx.wxID_EXIT, wx.wxEVT_COMMAND_MENU_SELECTED,
    function (event)
      frame:Close() 
    end )

  -- connect the selection event of the about menu item
  frame:Connect(wx.wxID_ABOUT, wx.wxEVT_COMMAND_MENU_SELECTED,
    function (event)
      wx.wxMessageBox('R3E Trace Viewer\n(c) 2015 Christoph Kubisch',
                      "About R3E Trace Viewer",
                      wx.wxOK + wx.wxICON_INFORMATION,
                      frame)
    end )
  
  local tools       = wx.wxPanel  ( frame, wx.wxID_ANY )
  local toolsTime   = wx.wxWindow ( tools, wx.wxID_ANY )
  local toolsAction = wx.wxWindow ( tools, wx.wxID_ANY )
  local sizer = wx.wxBoxSizer(wx.wxVERTICAL)
  sizer:Add(toolsAction, 0, wx.wxEXPAND)
  sizer:Add(toolsTime, 0, wx.wxEXPAND)
  tools:SetSizer(sizer)
  
  frame.tool = tools
  
  local ID_BTNRANGE = NewID()
  
  local lbltime = wx.wxStaticText(toolsTime, wx.wxID_ANY, "Time:", wx.wxDefaultPosition, wx.wxSize(30,24), wx.wxALIGN_RIGHT)
  local txttime = wx.wxTextCtrl(toolsTime, ID_TXTTIME, "0", wx.wxDefaultPosition, wx.wxSize(78,24), wx.wxTE_READONLY)
  local btnrange = wx.wxButton(toolsTime, ID_BTNRANGE, "Range Begin",wx.wxDefaultPosition, wx.wxSize(80,24))
  local slider  = wx.wxSlider(toolsTime, ID_SLIDER, 0, 0, constants.SLIDER_RES, wx.wxDefaultPosition, wx.wxSize(80,24))
  
  
  -- wx.wxArtProvider.GetBitmap(wx.wxART_REPORT_VIEW, wx.wxART_MENU, wx.wxSize(16,16))
  local btnexport = wx.wxButton( toolsAction, ID_BTNEXPORT, "Export Sel. Props",wx.wxDefaultPosition, wx.wxSize(116,24))
  btnexport:SetToolTip("Export selected properties to .csv")
  local btnplot = wx.wxButton( toolsAction, ID_BTNPLOT, "Plot Sel. Props",wx.wxDefaultPosition, wx.wxSize(100,24))
  local lblgrad = wx.wxStaticText(toolsAction, wx.wxID_ANY, "Gradient (1/100s):", wx.wxDefaultPosition, wx.wxSize(96,24), wx.wxALIGN_RIGHT)
  local spngrad = wx.wxSpinCtrl(toolsAction, ID_SPNGRAD, "", wx.wxDefaultPosition, wx.wxSize(50,24), wx.wxSP_ARROW_KEYS + wx.wxTE_PROCESS_ENTER)
  
  local lblplot = wx.wxStaticText(toolsAction, wx.wxID_ANY, "Selector", wx.wxDefaultPosition, wx.wxSize(50,24), wx.wxALIGN_RIGHT)
  local lblvis  = wx.wxStaticText(toolsAction, wx.wxID_ANY, "Visible", wx.wxDefaultPosition, wx.wxSize(40,24), wx.wxALIGN_RIGHT)
  
  local spnwidth = wx.wxSpinCtrl(toolsAction, ID_SPNWIDTH, "", wx.wxDefaultPosition, wx.wxSize(60,24),
    wx.wxSP_ARROW_KEYS + wx.wxTE_PROCESS_ENTER, 1, 100, 10)
  
  local radios = {}
  for i=1,constants.MAX_PLOTS do
    local id  = NewID()
    local rad = wx.wxRadioButton(toolsAction, id, string.char(64+i), wx.wxDefaultPosition, wx.wxDefaultSize,  i==1 and wx.wxRB_GROUP or 0)
    rad.id = id
    radios[i] = rad
  end
  local checks = {}
  for i=1,constants.MAX_PLOTS do
    local id  = NewID()
    local chk = wx.wxCheckBox(toolsAction, id, string.char(64+i), wx.wxDefaultPosition, wx.wxDefaultSize)
    if (i == 1) then chk:SetValue(true) end
    chk.id = id
    checks[i] = chk
  end
  local ID_CHKANIM = NewID()
  local chkanim = wx.wxCheckBox(toolsAction, ID_CHKANIM, "Animated\ndriving line", wx.wxDefaultPosition, wx.wxDefaultSize)
  
  frame.btnexport = btnexport
  frame.btnplot = btnplot
  frame.lbltime = lbltime
  frame.txttime = txttime
  frame.lblgrad = lblgrad
  frame.spngrad = spngrad
  frame.slider  = slider
  frame.radios  = radios
  frame.checks  = checks
  frame.chkanim = chkanim
  frame.btnrange = btnrange
  
  local sizer = wx.wxBoxSizer(wx.wxHORIZONTAL)
  sizer:Add(lbltime, 0, wx.wxALL,4)
  sizer:Add(txttime, 0, wx.wxALL)
  sizer:Add(btnrange,  0, wx.wxALL)
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
  sizer:Add(chkanim,  0, wx.wxLEFT,4)
  toolsAction:SetSizer(sizer)
  
  local sizer = wx.wxBoxSizer(wx.wxVERTICAL)
  sizer:Add(tools,0, wx.wxEXPAND)
  sizer:Add(winManaged,1, wx.wxEXPAND)
  frame:SetSizer(sizer)
  
  -- add lap sidebar
  local lapview = initLapView(winManaged, ID_LAP)
  frame.lapview = lapview
  
  -- add property
  local propview = initPropertyView(winManaged, ID_PROPERTY)
  frame.propview = propview
  
  local trackview = initTrackView(winManaged, ID_TRACK)
  frame.trackview = trackview

  local function wxT(s) return s end

  mgr:AddPane(lapview, wxaui.wxAuiPaneInfo():
          Name(wxT("laps")):Caption(wxT("Laps")):
          Left():Layer(1):BestSize(lapview:GetSize()):MinSize(wx.wxSize(100,100)):
          CloseButton(false):MaximizeButton(true));
        
  mgr:AddPane(propview, wxaui.wxAuiPaneInfo():
          Name(wxT("props")):Caption(wxT("Properties")):
          Left():Layer(0):BestSize(propview:GetSize()):MinSize(wx.wxSize(100,100)):
          CloseButton(false):MaximizeButton(true));
        
  mgr:AddPane(trackview, wxaui.wxAuiPaneInfo():
          Name(wxT("track")):Caption(wxT("Track")):
          Center():BestSize(trackview:GetSize()):MinSize(wx.wxSize(100,100)):
          CloseButton(false):MaximizeButton(true));
        
  mgr:Update()
  
  local function settingsSave()
    settings:Write("Version", 1)
    settings:Write("TrackWidth", gfx.widthmul)
    settings:Write("MainManaged", mgr:SavePerspective())
    settingsSaveFramePosition(frame, "MainFrame")
  end

  local function settingsRestore()
    settingsRestoreFramePosition(frame, "MainFrame")
    local layoutcur = mgr:SavePerspective()
    local layout = settingsReadSafe(settings,"MainManaged",layoutcur)
    if (layout ~= layoutcur) then
      layout = layout:gsub("minw=[%-%d]+;","minw=100;"):gsub("minh=[%-%d]+;","minh=100;")
      mgr:LoadPerspective(layout)
    end
    
    gfx.widthmul = settingsReadSafe(settings,"TrackWidth", 1)
    spnwidth:SetValue( gfx.widthmul * 10)
  end
  
  -- load layout
  settingsRestore()
 
  ----------
  -- events
  
  local function timelap()
    -- reset
    slider:SetValue(0)
    txttime:ChangeValue("0")
  end
  sys.registerHandler(events.lap, timelap)
  
  local function setVisible(i, state)
    checks[i]:SetValue(state)
    gfx.enabled[i] = state
  end
  
  frame:Connect(ID_TIMER, wx.wxEVT_TIMER,
    function(event)
      trackview:Refresh()
    end)
  
  frame:Connect(ID_LAP, wx.wxEVT_COMMAND_LIST_ITEM_ACTIVATED,
  function (event)
    if (not active.trace) then return end
    
    setVisible(gfx.plot.idx, true)
    
    local trace,lap = lapview.getFromIdx(event:GetIndex())
    sys.traceSetLap( trace, lap)
  end)

  frame:Connect(ID_LAP, wx.wxEVT_COMMAND_LIST_ITEM_RIGHT_CLICK,
  function (event)
    if (not (active.trace and gfx.avg) ) then return end
    
    setVisible(gfx.plot.idx, true)
    
    local trace,lap = lapview.getFromIdx(event:GetIndex())
    
    sys.triggerEvent(events.compare, trace, lap, spngrad:GetValue())
    trackview.changed()
  end)

  tools:Connect(ID_CHKANIM, wx.wxEVT_COMMAND_CHECKBOX_CLICKED,
    function (event)
      if (event:IsChecked()) then
        timer:Start(16)
        if (config.viewer.animationremoveslabel) then trackview.lbl:Hide() end
      else
        if (config.viewer.animationremoveslabel) then trackview.lbl:Show() end
        timer:Stop()
      end
    end)
  
  local function spinwidthEvent(event)
    gfx.widthmul = spnwidth:GetValue()/10
    trackview.canvas:Refresh()
  end
  
  tools:Connect(ID_SPNWIDTH, wx.wxEVT_COMMAND_TEXT_ENTER, spinwidthEvent)
  tools:Connect(ID_SPNWIDTH, wx.wxEVT_COMMAND_SPINCTRL_UPDATED, spinwidthEvent)
  
  local function gradientEvent(event)
    sys.traceSetGradient ( spngrad:GetValue() )
  end
  tools:Connect(ID_SPNGRAD, wx.wxEVT_COMMAND_TEXT_ENTER, gradientEvent)
  tools:Connect(ID_SPNGRAD, wx.wxEVT_COMMAND_SPINCTRL_UPDATED, gradientEvent)

  local rangeState = nil
  local function updateRangeText()
    btnrange:SetLabel(rangeState == "begin" and "Range End" or 
                      rangeState == "end" and "Range Clear" or
                      "Range Begin")
  end
  
  tools:Connect(ID_BTNRANGE, wx.wxEVT_COMMAND_BUTTON_CLICKED,
    function(event)
      if (rangeState == nil) then
        rangeState = "begin"
        sys.triggerEvent(events.range, rangeState)
      elseif (rangeState == "begin") then
        rangeState = "end"
        sys.triggerEvent(events.range, rangeState)
      else
        rangeState = nil
        sys.triggerEvent(events.range, rangeState)
      end
      updateRangeText()
      trackview.canvas:Refresh()
    end)
  
  sys.registerHandler(events.open, 
    function() 
      rangeState = nil
      updateRangeText()
      sys.triggerEvent(events.range, rangeState)
    end)
  
  tools:Connect(ID_SLIDER, wx.wxEVT_COMMAND_SLIDER_UPDATED,
  function (event)
    if (not active.lapData) then return end
    
    local fracc = event:GetInt()/(constants.SLIDER_RES-1)
    local laptime = active.lapData.time * fracc
    local time = active.lapData.timeBegin + laptime
    
    sys.traceSetTime(time)
    txttime:ChangeValue(toMS(laptime))
  end)

  for i=1,constants.MAX_PLOTS do
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

  propview:Connect(ID_PROPERTY, wx.wxEVT_COMMAND_LIST_ITEM_ACTIVATED,
    function (event)
      local active = gfx.plot.idx
      
      setVisible(active, true)
      
      sys.traceSetProperty(propview.getSelected(1), spngrad:GetValue())
      trackview.changed()
    end)

  tools:Connect(ID_BTNPLOT, wx.wxEVT_COMMAND_BUTTON_CLICKED,
    function (event)
      local selected = propview.getSelected(4)
      local num = helpers.getNumSelected(selected)
      local active = gfx.plot.idx
      
      for i=1,constants.MAX_PLOTS do
        setVisible(i, false)
      end
      
      if (num == 1) then
        setVisible(active, true)
        sys.traceSetProperty(selected, spngrad:GetValue())
      elseif( num > 1) then
        for i=1,num do
          local sel = {props={ selected.props[i] }, }
          sel.fnaccess = r3emap.makeAccessor(sel.props, config.viewer.convertvalues)
          
          gfx.plot = gfx.plots[i]
          setVisible(i, true)
          
          sys.traceSetProperty(sel, spngrad:GetValue())
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
        sys.traceSaveCSV(propview.getSelected(), spngrad:GetValue(), fileDialog:GetPath() )
      end
      fileDialog:Destroy()
    end )
  
  frame:Connect(wx.wxID_OPEN, wx.wxEVT_COMMAND_MENU_SELECTED,
    function (event) 
      local fileDialog = wx.wxFileDialog( frame, "Open file", "", "","R3E trace files (*.r3t)|*.r3t",
                                          wx.wxFD_OPEN + wx.wxFD_FILE_MUST_EXIST)

      if fileDialog:ShowModal() == wx.wxID_OK then
        sys.traceOpenFile(fileDialog:GetPath())
      end
      fileDialog:Destroy()
    end )
  
  frame:Connect(ID_MENUAPPEND, wx.wxEVT_COMMAND_MENU_SELECTED,
    function (event) 
      local fileDialog = wx.wxFileDialog( frame, "Append file", "", "","R3E trace files (*.r3t)|*.r3t",
                                          wx.wxFD_OPEN + wx.wxFD_FILE_MUST_EXIST)

      if fileDialog:ShowModal() == wx.wxID_OK then
        sys.traceAppendFile(fileDialog:GetPath())
      end
      fileDialog:Destroy()
    end )

  frame:Connect(ID_MENUEXPORT, wx.wxEVT_COMMAND_MENU_SELECTED,
    function (event) 
      local fileDialog = wx.wxFileDialog( frame, "Save Session as", "", "","CSV files (*.csv)|*.csv",
                                          wx.wxFD_SAVE)

      if fileDialog:ShowModal() == wx.wxID_OK then
        sys.traceSessionSaveCSV(fileDialog:GetPath())
      end
      fileDialog:Destroy()
    end )
  
  frame:Connect(ID_MAIN, wx.wxEVT_CLOSE_WINDOW,
    function(event)
      if (timer:IsRunning()) then timer:Stop() end
      
      settingsSave()
      
      frame:Destroy()
    end)
  
  return frame
end

app = initApp()
gAPP.app = app

local args = _ARGS or {...}
sys.traceOpenFile(args[2] or args[1]==nil and "trace_150712_170141.r3t")

-- show the frame window
app:Show(true)
wx.wxGetApp():MainLoop()