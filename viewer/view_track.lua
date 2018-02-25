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
local constants = gCONSTANTS

local gfx = gGFX


---------------------------------------------
local function initTrackView(frame, ID_TRACK)
  local init = true
  
  --local subframe = wx.wxWindow(frame, ID_TRACK)
  
  local canvas = wx.wxGLCanvas(subframe or frame, ID_TRACK, {
  wx.WX_GL_RGBA, 1, wx.WX_GL_DOUBLEBUFFER, 1, 
  wx.WX_GL_MIN_RED, 8, wx.WX_GL_MIN_GREEN, 8, wx.WX_GL_MIN_BLUE, 8, wx.WX_GL_MIN_ALPHA, 8,
  wx.WX_GL_STENCIL_SIZE, 0, wx.WX_GL_DEPTH_SIZE, 0, wx.wx_GL_COMPAT_PROFILE, 0
  },
  wx.wxDefaultPosition, wx.wxSize(512,512), wx.wxEXPAND + wx.wxFULL_REPAINT_ON_RESIZE)

  subframe = subframe or canvas

  local lbl = wx.wxStaticText(subframe, wx.wxID_ANY, " No Data ")
  subframe.lbl = lbl
  subframe.canvas = canvas
  
  if (subframe ~= canvas) then
    local sizer = wx.wxBoxSizer(wx.wxVERTICAL)
    sizer:Add(panel, 0, wx.wxALL)
    sizer:Add(canvas, 1, wx.wxEXPAND)
    subframe:SetSizer(sizer)
    subframe.sizer = sizer
  end
  
  local context = gfx.createSharedContext(canvas)
  
  local res = ffi.new("GLuint[1]")
  gl.glGenTextures(1, res)
  local tex = res[0]
  gl.glGenFramebuffers(1, res)
  local fbo = res[0]
  
  local lastw,lasth
  
  local ctrl = glu.getOrthoCtrl()
  
  local function render()
    --local dc = wx.wxPaintDC(canvas)
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
      gfx.drawTrack(w,h,ctrl.zoom,ctrl.pan)
    end

    gl.glBindFramebuffer( gl.GL_DRAW_FRAMEBUFFER, 0)
    gl.glBlitFramebuffer( 0,0, w, h, 0,0, w, h, gl.GL_COLOR_BUFFER_BIT, gl.GL_LINEAR)
    canvas:SwapBuffers()
    --dc:delete()
  end
  
  function subframe.changed()
    local txt = ""
    local first = true
    local num = 0
    for i=1,constants.MAX_PLOTS do
      if (gfx.enabled[i] and gfx.plots[i].trace) then
        local plot = gfx.plots[i]
        txt = txt..(first and "" or "\n")..plot.info
        first = false
        num = num + 1
      end
    end
    if (num > 1) then
      txt = "Plot order left to right:\n"..txt
    end
    lbl:SetLabel(txt)
    subframe:Refresh()
  end
  
  canvas:Connect(wx.wxEVT_PAINT, render)
  
  local lb = false
  local rb = false
  
  local function updateCtrl(event)
    local sz = canvas:GetSize()
    local w,h = sz:GetWidth(), sz:GetHeight()
    ctrl:update( w, h, event:GetX(), event:GetY(), lb, rb)
    canvas:Refresh()
  end
  
  local function OnDown(event)
    if (not canvas:HasCapture()) then canvas:CaptureMouse() end
    lb = event:LeftIsDown()
    rb = event:RightIsDown()
    updateCtrl(event)
  end

  local function OnUp(event)
    if lb or rb then
      if canvas:HasCapture() then canvas:ReleaseMouse() end
      lb = false
      rb = false
      updateCtrl(event)
    end
  end

  local function OnMotion(event)
    if lb or rb then
      updateCtrl(event)
    elseif canvas:HasCapture() then -- just in case we lost focus somehow
      canvas:ReleaseMouse()
      lb = false
      rb = false
      updateCtrl(event)
    end
  end
  
  canvas:Connect(wx.wxEVT_LEFT_DOWN,  OnDown )
  canvas:Connect(wx.wxEVT_LEFT_UP,    OnUp )
  canvas:Connect(wx.wxEVT_RIGHT_DOWN, OnDown )
  canvas:Connect(wx.wxEVT_RIGHT_UP,   OnUp )
  canvas:Connect(wx.wxEVT_MOTION,     OnMotion )
  
  sys.registerHandler(sys.events.time, function() subframe.changed() end)
  
  return subframe
end

return initTrackView
