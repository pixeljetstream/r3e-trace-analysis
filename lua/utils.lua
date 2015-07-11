local lfs = require "lfs"
local ffi = require "ffi"

ffi.cdef "void Sleep(int ms);\n"

local _M = {}
function _M.sleep(s)
  ffi.C.Sleep(s)
end
function _M.collectFiles(path, matchstr, subdirs, callback)
  
  local doesMatch
  if type(matchstr) == "string" then
    doesMatch = function(file)
      return file:match(matchstr)
    end
  elseif type(matchstr) == "table" then
    doesMatch = function(file)
      for i,v in ipairs(matchstr) do
        if (file:match(v)) then
          return true
        end
      end
    end
  end
  
  local function collect(path)
    for file in lfs.dir(path) do
      if file ~= "." and file ~= ".." then
        local f = path..'/'..file
        local attr = lfs.attributes (f)

        if attr.mode == "directory" then
          if (subdirs) then
            collect(f)
          end
        else
          if doesMatch(file:lower()) then
            callback(f,file)
          end
        end
      end
    end
  end
  
  collect(path)
end

function _M.tableFlatClone(tab)
  local new = {}
  for i,v in pairs(tab) do
    new[i] = v
  end
  
  return new
end

function _M.loadInto(filename, tab)
  fn,err = loadfile(filename)
  if (not fn) then
    print(err)
    return
  end
  setfenv(fn, tab)()
end


local counter = 0
function _M.unique()
  counter = counter +1
  return counter
end

return _M
