local ffi = require "ffi"

local R3E_SHARED_MEMORY_NAME = "$Race$"

local R3E_DEFS = [[
  
typedef int32_t r3e_int32;
typedef float r3e_float32;
typedef double r3e_float64;
  
#pragma pack(1)

typedef struct
{
    r3e_float32 X;
    r3e_float32 Y;
    r3e_float32 Z;
} r3e_vec3_f32;

typedef struct
{
    r3e_float64 X;
    r3e_float64 Y;
    r3e_float64 Z;
} r3e_vec3_f64;

typedef struct
{
    r3e_float32 Pitch;
    r3e_float32 Yaw;
    r3e_float32 Roll;
} r3e_orientation_f32;

typedef struct
{
    r3e_float32 FrontLeft_Left;
    r3e_float32 FrontLeft_Center;
    r3e_float32 FrontLeft_Right;

    r3e_float32 FrontRight_Left;
    r3e_float32 FrontRight_Center;
    r3e_float32 FrontRight_Right;

    r3e_float32 RearLeft_Left;
    r3e_float32 RearLeft_Center;
    r3e_float32 RearLeft_Right;

    r3e_float32 RearRight_Left;
    r3e_float32 RearRight_Center;
    r3e_float32 RearRight_Right;
} r3e_tiretemps;

// High precision data for player's vehicle only
typedef struct
{
    // Virtual physics time
    // Unit: Ticks (1 tick = 1/400th of a second)
    r3e_int32 GameSimulationTicks;

    // Padding to accomodate for legacy alignment
    r3e_int32 _padding1;

    // Virtual physics time
    // Unit: Seconds
    r3e_float64 GameSimulationTime;

    // Car world-space position
    r3e_vec3_f64 Position;

    // Car world-space velocity
    // Unit: Meter per second (m/s)
    r3e_vec3_f64 Velocity;

    // Car world-space acceleration
    // Unit: Meter per second squared (m/s^2)
    r3e_vec3_f64 Acceleration;

    // Car local-space acceleration
    // Unit: Meter per second squared (m/s^2)
    r3e_vec3_f64 LocalAcceleration;

    // Car body orientation
    // Unit: Euler angles
    r3e_vec3_f64 Orientation;

    // Car body rotation
    r3e_vec3_f64 Rotation;

    // Car body angular acceleration (torque divided by inertia)
    r3e_vec3_f64 AngularAcceleration;

    // Acceleration of driver's body in local coordinates
    r3e_vec3_f64 DriverBodyAcceleration;
} r3e_playerdata;

typedef struct
{
  // -1 = no data
  //  0 = not active
  //  1 = active
  r3e_int32 Yellow;
  r3e_int32 Blue;
  r3e_int32 Black;
} r3e_flags;

typedef struct
{
  r3e_float32 Engine;
  r3e_float32 Transmission;
  r3e_float32 Aerodynamics;
  r3e_float32 TireFrontLeft;
  r3e_float32 TireFrontRight;
  r3e_float32 TireRearLeft;
  r3e_float32 TireRearRight;
} r3e_cardamage;

typedef struct
{
  r3e_float32 FrontLeft;
  r3e_float32 FrontRight;
  r3e_float32 RearLeft;
  r3e_float32 RearRight;
} r3e_tirepressure;

typedef struct
{
  r3e_float32 FrontLeft;
  r3e_float32 FrontRight;
  r3e_float32 RearLeft;
  r3e_float32 RearRight;
} r3e_braketemperatures;

typedef struct
{
  // ...
  r3e_int32 DriveThrough;

  // ...
  r3e_int32 StopAndGo;

  // ...
  r3e_int32 PitStop;

  // ...
  r3e_int32 TimeDeduction;

  // ...
  r3e_int32 SlowDown;
} r3e_cuttrackpenalties;

typedef struct
{
  r3e_float32 Sector1;
  r3e_float32 Sector2;
  r3e_float32 Sector3;
} r3e_sectors;

typedef struct
{
    // Deprecated
    r3e_float32 user_input[6];

    // Engine speed
    // Unit: Radians per second (rad/s)
    r3e_float32 EngineRps;

    // Maximum engine speed
    // Unit: Radians per second (rad/s)
    r3e_float32 MaxEngineRps;

    // Unit: Kilopascals (KPa)
    r3e_float32 FuelPressure;

    // Current amount of fuel in the tank(s)
    // Unit: Liters (l)
    r3e_float32 FuelLeft;

    // Maximum capacity of fuel tank(s)
    // Unit: Liters (l)
    r3e_float32 FuelCapacity;

    // Unit: Celsius (C)
    r3e_float32 EngineWaterTemp;

    // Unit: Celsius (C)
    r3e_float32 EngineOilTemp;

    // Unit: Kilopascals (KPa)
    r3e_float32 EngineOilPressure;

    // Unit: Meter per second (m/s)
    r3e_float32 CarSpeed;

    // Total number of laps in the race, or -1 if player is not in race mode (practice, test mode, etc.)
    r3e_int32 NumberOfLaps;

    // How many laps the player has completed. If this value is 6, the player is on his 7th lap. -1 = n/a
    r3e_int32 CompletedLaps;

    // Unit: Seconds (-1.0 = none)
    r3e_float32 LapTimeBest;

    // Unit: Seconds (-1.0 = none)
    r3e_float32 LapTimePrevious;

    // Unit: Seconds (-1.0 = none)
    r3e_float32 LapTimeCurrent;

    // Current position (1 = first place)
    r3e_int32 Position;

    // Number of cars (including the player) in the race
    r3e_int32 NumCars;

    // -2 = no data
    // -1 = reverse,
    //  0 = neutral
    //  1 = first gear
    // (... up to 7th)
    r3e_int32 Gear;

    // Temperature of three points across the tread of each tire
    // Unit: Celsius (C)
    r3e_tiretemps TireTemp;

    // Number of penalties pending for the player
    r3e_int32 NumPenalties;

    // Physical location of car's center of gravity in world space (X, Y, Z) (Y = up)
    r3e_vec3_f32 CarCgLoc;

    // Pitch, yaw, roll
    // Unit: Radians (rad)
    r3e_orientation_f32 CarOrientation;

    // Acceleration in three axes (X, Y, Z) of car body in local-space.
    // From car center, +X=left, +Y=up, +Z=back.
    // Unit: Meter per second squared (m/s^2)
    r3e_vec3_f32 LocalAcceleration;

    // -1 = no data for DRS
    //  0 = not available
    //  1 = available
    r3e_int32 DrsAvailable;

    // -1 = no data for DRS
    //  0 = not engaged
    //  1 = engaged
    r3e_int32 DrsEngaged;

    // Padding to accomodate for legacy alignment
    r3e_int32 _padding1;

    // High precision data for player's vehicle only
    r3e_playerdata Player;
    
    // ...
    r3e_int32 EventIndex;

    // ...
    r3e_int32 SessionType;

    // ...
    r3e_int32 SessionPhase;

    // ...
    r3e_int32 SessionIteration;

    // ...
    r3e_int32 ControlType;

    // ...
    r3e_float32 ThrottlePedal;

    // ...
    r3e_float32 BrakePedal;

    // ...
    r3e_float32 ClutchPedal;

    // ...
    r3e_float32 BrakeBias;

    // ...
    r3e_tirepressure TirePressure;

    // ...
    r3e_int32 TireWearActive;

    // ...
    r3e_int32 TireType;

    // ...
    r3e_braketemperatures BrakeTemperatures;

    // -1 = no data
    //  0 = not active
    //  1 = active
    r3e_int32 FuelUseActive;

    // ...
    r3e_float32 SessionTimeRemaining;

    // ...
    r3e_float32 LapTimeBestLeader;

    // ...
    r3e_float32 LapTimeBestLeaderClass;

    // ...
    r3e_float32 LapTimeDeltaSelf;

    // ...
    r3e_float32 LapTimeDeltaLeader;

    // ...
    r3e_float32 LapTimeDeltaLeaderClass;

    // ...
    r3e_sectors SectorTimeDeltaSelf;

    // ...
    r3e_sectors SectorTimeDeltaLeader;

    // ...
    r3e_sectors SectorTimeDeltaLeaderClass;

    // ...
    r3e_float32 TimeDeltaFront;

    // ...
    r3e_float32 TimeDeltaBehind;

    // ...
    r3e_int32 PitWindowStatus;

    // The minute/lap into which you're allowed/obligated to pit
    // Unit: Minutes in time-based sessions, otherwise lap
    r3e_int32 PitWindowStart;

    // The minute/lap into which you can/should pit
    // Unit: Minutes in time based sessions, otherwise lap
    r3e_int32 PitWindowEnd;

    // Total number of cut track warnings
    r3e_int32 CutTrackWarnings;

    // ...
    r3e_cuttrackpenalties Penalties;

    // ...
    r3e_flags Flags;

    // ...
    r3e_cardamage CarDamage;
} r3e_shared;
]])

-- windows internals
ffi.cdef(R3E_DEFS)

ffi.cdef([[
  typedef void* HANDLE;
  typedef int BOOL;
  typedef unsigned long DWORD;
  typedef const char* LPCSTR;
  typedef const void* LPCVOID;
  typedef void* LPVOID;
  typedef size_t SIZE_T;
  typedef unsigned long ULONG_PTR;
  typedef long LONG;
  typedef char CHAR;
  
  DWORD GetLastError();
  
  enum {
    MAX_PATH = 260,
  
    FILE_MAP_COPY       = 0x0001,
    FILE_MAP_WRITE      = 0x0002,
    FILE_MAP_READ       = 0x0004,
    
    PAGE_READONLY       = 0x02,
    PAGE_READWRITE      = 0x04,
    
    TH32CS_SNAPPROCESS  = 0x0002,
  };
  
  typedef struct tagPROCESSENTRY32
  {
      DWORD   dwSize;
      DWORD   cntUsage;
      DWORD   th32ProcessID;          // this process
      ULONG_PTR th32DefaultHeapID;
      DWORD   th32ModuleID;           // associated exe
      DWORD   cntThreads;
      DWORD   th32ParentProcessID;    // this process's parent process
      LONG    pcPriClassBase;         // Base priority of process's threads
      DWORD   dwFlags;
      CHAR    szExeFile[MAX_PATH];    // Path
  } PROCESSENTRY32;
  typedef PROCESSENTRY32 *  PPROCESSENTRY32;
  typedef PROCESSENTRY32 *  LPPROCESSENTRY32;

  BOOL
  Process32First(
    HANDLE hSnapshot,
    LPPROCESSENTRY32 lppe
    );

  BOOL
  Process32Next(
    HANDLE hSnapshot,
    LPPROCESSENTRY32 lppe
    );
      
  HANDLE
  CreateToolhelp32Snapshot(
    DWORD dwFlags,
    DWORD th32ProcessID
    );
  
  HANDLE 
  OpenFileMappingA(
    DWORD dwDesiredAccess,
    BOOL bInheritHandle,
    LPCSTR lpName
    );
    
  HANDLE
  CreateFileMappingA(
    HANDLE hFile,
    void* lpFileMappingAttributes,
    DWORD flProtect,
    DWORD dwMaximumSizeHigh,
    DWORD dwMaximumSizeLow,
    LPCSTR lpName
    );
  
  BOOL CloseHandle(HANDLE);
  
  LPVOID
  MapViewOfFile(
    HANDLE hFileMappingObject,
    DWORD dwDesiredAccess,
    DWORD dwFileOffsetHigh,
    DWORD dwFileOffsetLow,
    SIZE_T dwNumberOfBytesToMap
    );
    
  BOOL
  FlushViewOfFile(
    LPCVOID lpBaseAddress,
    SIZE_T dwNumberOfBytesToFlush
    );
    
  BOOL
  UnmapViewOfFile(
    LPCVOID lpBaseAddress
    );
]])

local r3e_shared_type     = ffi.typeof("r3e_shared")
local r3e_shared_type_ptr = ffi.typeof("r3e_shared*")
local r3e_shared_size     = ffi.sizeof("r3e_shared")

print ("r3e sizeof shared", ffi.sizeof(r3e_shared_type))

local _M = {
  RPS_TO_RPM = (60 / (2 * math.pi)),
  MPS_TO_KPH = 3.6,
  SHARED_TYPE = r3e_shared_type,
  SHARED_TYPE_NAME = "r3e_shared",
  SHARED_SIZE = r3e_shared_size,
  DEFS = R3E_DEFS,
  
  Session = {
      Unavailable = -1,
      Practice = 0,
      Qualify = 1,
      Race = 2
  },

  SessionPhase = {
      Unavailable = -1,
      Garage = 0,
      Gridwalk = 1,
      Formation = 3,
      Countdown = 4,
      Green = 5,
      Checkered = 6
  },

  Control = {
      Unavailable = -1,
      Player = 0,
      AI = 1,
      Remote = 2,
      Replay = 3
  },

  PitWindow = {
      Unavailable = -1,
      Disabled = 0,
      Closed = 1,
      Open = 2,
      Completed = 3
  },

  TireType = {
      Unavailable = -1,
      Option = 0,
      Prime = 1
  },
}

local function isProcessRunning(name)
  local entry    = ffi.new("PROCESSENTRY32")
  ffi.fill(entry,0)
  entry.dwSize = ffi.sizeof("PROCESSENTRY32");

  local snapshot = ffi.C.CreateToolhelp32Snapshot(ffi.C.TH32CS_SNAPPROCESS, 0);
  if (ffi.C.Process32First(snapshot, entry) ~= 0) then
    while (ffi.C.Process32Next(snapshot, entry) ~= 0) do
      if (ffi.string(entry.szExeFile) == name) then
        return true
      end
    end
  end

  return false
end

function _M.isR3Erunning()
  return _M.emulation or isProcessRunning("RRRE.exe")
end

local function open()
  return ffi.C.OpenFileMappingA(
        ffi.C.FILE_MAP_READ,
        0,
        R3E_SHARED_MEMORY_NAME);
end

local function create()
  local invalid = ffi.cast("HANDLE",ffi.cast("size_t",-1))
  return ffi.C.CreateFileMappingA(
        invalid,
        nil,
        ffi.C.PAGE_READWRITE,
        0,
        ffi.sizeof(r3e_shared_type),
        R3E_SHARED_MEMORY_NAME);
end

function _M.isMappable()
  local handle = open()
  if (handle ~= nil) then
    ffi.C.CloseHandle(handle)
  end
  return handle ~= nil
end

function _M.createMapping(writeonly)
  local filemap = writeonly and ffi.C.FILE_MAP_WRITE or ffi.C.FILE_MAP_READ
  local handle
  if (writeonly) then
    handle = create()
  else
    handle = open()
  end
  if (handle == nil) then
    error("could not open handle: "..ffi.C.GetLastError())
    return
  end
  
  local buffer = ffi.C.MapViewOfFile(handle, filemap, 0, 0, r3e_shared_size)
  buffer = ffi.cast(r3e_shared_type_ptr, buffer)
  if (buffer == nil) then
    error("could not map buffer: "..ffi.C.GetLastError())
    ffi.C.CloseHandle(handle)
    return
  end
  
 
  local map = {}
  print("r3edata map created", map, writeonly)
  
  if (writeonly) then
    function map:writeData(src)
      ffi.copy(buffer, src, r3e_shared_size)
    end
  else
    function map:readData(dst)
      ffi.copy(dst, buffer, r3e_shared_size)
    end
  end
  
  function map:destroy()
    ffi.C.UnmapViewOfFile(buffer)
    ffi.C.CloseHandle(handle)
    print("r3edata map destroyed", map, writeonly)
  end
  
  return map
end

-- module definition
return _M


