local gl  = require "glewgl"
local ffi = require "ffi"

local co = {}

function co.feedbackvaryings(prog,what,mode)
  local cptrs = ffi.new("const char*[?]",#what)
  for i,v in ipairs(what) do
    cptrs[i-1] = v
  end
  gl.glTransformFeedbackVaryings(prog, #what, cptrs, mode)
end

function co.genprogram(sources,prelink)
  local prog = gl.glCreateProgram()
  
  gl.glProgramParameteri(prog, gl.GL_PROGRAM_BINARY_RETRIEVABLE_HINT, gl.GL_TRUE)
  local status = ffi.new("GLint[1]",{0})
  for i,v in pairs(sources) do
    local shd = gl.glCreateShader(gl[i])
    local sourceptrs = ffi.new("const GLchar*[1]",{v})
    local lengthptrs = ffi.new("GLint[1]",{#v})
    gl.glShaderSource(shd,1,sourceptrs,lengthptrs)
    gl.glCompileShader(shd)
    gl.glGetShaderiv(shd,gl.GL_COMPILE_STATUS,status)
    if (status[0] ~= gl.GL_TRUE) then
      print(v,"\n")
      gl.glGetShaderiv(shd,gl.GL_INFO_LOG_LENGTH,status)
      local err = ffi.new("GLchar[?]",status[0]+1)
      gl.glGetShaderInfoLog(shd,status[0]+1,NULL,err)
      print("shader error",i,ffi.string(err,status[0]+1),"\n")
      return nil
    end
    gl.glAttachShader(prog,shd)
    gl.glDeleteShader(shd)
  end
  
  if (prelink) then
    prelink(prog)
  end
  
  gl.glLinkProgram(prog)
  gl.glGetProgramiv(prog, gl.GL_LINK_STATUS, status);

  if (status[0] ~= gl.GL_TRUE) then
    for i,v in pairs(sources) do
      print(i,"\n",v,"\n")
    end
    
    gl.glGetProgramiv(prog, gl.GL_INFO_LOG_LENGTH, status);
    local err = ffi.new("GLchar[?]",status[0]+1)
    gl.glGetProgramInfoLog(prog,status[0]+1,NULL,err)
    print("program error",ffi.string(err,status[0]),"\n")
    return nil
  end
  
  return prog
end


function co.loadfile(filename, how)
  local f = io.open(filename, how)
  if (not f) then return nil end
  local str = f:read("*a")
  f:close()
  return str
end

function co.loadprogram(filenames,prepend,prelink)
  local prepend = prepend or ""
  
  local sources = {}
  local filesokay = true
  for i,v in pairs(filenames) do
    local src = co.loadfile(v,"rt")
    filesokay = filesokay and (src ~= nil)
    sources[i] = prepend..(src or "")
  end
  
  if (filesokay) then
    -- load from files
    local prog = co.genprogram(sources,prelink)
    return prog
  else
    error("no program definition found, neither files, nor cache")
  end
  
end

local metauni = {}
metauni.__index = function(table, key) return rawget(table,key) or -1 end

function co.programuniforms(prog)
  local tab = {}
  
  setmetatable(tab,metauni)
  
  local query = ffi.new("GLint[?]",3)
  local name  = ffi.new("GLchar[?]",256)
  gl.glGetProgramiv(prog,gl.GL_ACTIVE_UNIFORMS,query)
  local cnt = query[0]
  for i=0,cnt-1 do
    gl.glGetActiveUniform(prog,i,256,query,query+1,query+2,name)
    tab[ffi.string(name,query[0])] = gl.glGetUniformLocation(prog,name)
  end
  
  return tab
end




function co.enabledebug()
  -- GLenum source, GLenum type, GLuint id, GLenum severity, GLsizei length, const GLchar* message, GLvoid* userParam
  
  local keys = {
    GL_DEBUG_SOURCE_API_ARB                             = 0x8246,
    GL_DEBUG_SOURCE_WINDOW_SYSTEM_ARB                   = 0x8247,
    GL_DEBUG_SOURCE_SHADER_COMPILER_ARB                 = 0x8248,
    GL_DEBUG_SOURCE_THIRD_PARTY_ARB                     = 0x8249,
    GL_DEBUG_SOURCE_APPLICATION_ARB                     = 0x824A,
    GL_DEBUG_SOURCE_OTHER_ARB                           = 0x824B,
    GL_DEBUG_TYPE_ERROR_ARB                             = 0x824C,
    GL_DEBUG_TYPE_DEPRECATED_BEHAVIOR_ARB               = 0x824D,
    GL_DEBUG_TYPE_UNDEFINED_BEHAVIOR_ARB                = 0x824E,
    GL_DEBUG_TYPE_PORTABILITY_ARB                       = 0x824F,
    GL_DEBUG_TYPE_PERFORMANCE_ARB                       = 0x8250,
    GL_DEBUG_TYPE_OTHER_ARB                             = 0x8251,
    GL_DEBUG_SEVERITY_HIGH_ARB                          = 0x9146,
    GL_DEBUG_SEVERITY_MEDIUM_ARB                        = 0x9147,
    GL_DEBUG_SEVERITY_LOW_ARB                           = 0x9148,
  }
  local values = {}
  for i,v in pairs(keys) do values[v] = i end
     
  gl.glEnable(gl.GL_DEBUG_OUTPUT);
  
  local dbgfunc = ffi.cast("void (__stdcall *)(GLenum source, GLenum type, GLuint id, GLenum severity, GLsizei length, const GLchar* message, GLvoid* userParam)",function(source,typ,id,severity,length,message,userParam)
      print(values[tonumber(source)])
      print(values[tonumber(typ)])
      print(values[tonumber(severity)])
      print("id", tonumber(id))
      print( ffi.string(message) )
      if (typ == gl.GL_DEBUG_TYPE_ERROR) then
        print(debug.traceback("",2))
        io.flush()
        os.exit(0)
      end
    end)
  
  gl.glDebugMessageCallbackARB(dbgfunc,nil)
  gl.glEnable(gl.GL_DEBUG_OUTPUT_SYNCHRONOUS_ARB);
end

return co