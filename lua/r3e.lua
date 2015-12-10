local ffi = require "ffi"

local R3E_SHARED_MEMORY_NAME = "$Race$"

local R3E_DEFS_COMMON = [[
  
typedef int32_t r3e_int32;
typedef float r3e_float32;
typedef double r3e_float64;
typedef uint8_t r3e_u8char;
  
#pragma pack(1)

typedef enum
{
    R3E_SESSION_UNAVAILABLE = -1,
    R3E_SESSION_PRACTICE = 0,
    R3E_SESSION_QUALIFY = 1,
    R3E_SESSION_RACE = 2,
} r3e_session;

typedef enum
{
    R3E_SESSION_PHASE_UNAVAILABLE = -1,

    // Currently in garage
    R3E_SESSION_PHASE_GARAGE = 1,

    // Gridwalk or track walkthrough
    R3E_SESSION_PHASE_GRIDWALK = 2,

    // Formation lap, rolling start etc.
    R3E_SESSION_PHASE_FORMATION = 3,

    // Countdown to race is ongoing
    R3E_SESSION_PHASE_COUNTDOWN = 4,

    // Race is ongoing
    R3E_SESSION_PHASE_GREEN = 5,

    // End of session
    R3E_SESSION_PHASE_CHECKERED = 6,
} r3e_session_phase;

typedef enum
{
    R3E_CONTROL_UNAVAILABLE = -1,

    // Controlled by the actual player
    R3E_CONTROL_PLAYER = 0,

    // Controlled by AI
    R3E_CONTROL_AI = 1,

    // Controlled by a network entity of some sort
    R3E_CONTROL_REMOTE = 2,

    // Controlled by a replay or ghost
    R3E_CONTROL_REPLAY = 3,
} r3e_control;

typedef enum
{
    R3E_PIT_WINDOW_UNAVAILABLE = -1,

    // Pit stops are not enabled for this session
    R3E_PIT_WINDOW_DISABLED = 0,

    // Pit stops are enabled, but you're not allowed to perform one right now
    R3E_PIT_WINDOW_CLOSED = 1,

    // Allowed to perform a pit stop now
    R3E_PIT_WINDOW_OPEN = 2,

    // Currently performing the pit stop changes (changing driver, etc.)
    R3E_PIT_WINDOW_STOPPED = 3,

    // After the current mandatory pitstop have been completed
    R3E_PIT_WINDOW_COMPLETED = 4,
} r3e_pit_window;

typedef enum
{
    // No mandatory pitstops
    R3E_PITSTOP_STATUS_UNAVAILABLE = -1,

    // Mandatory pitstop not served yet
    R3E_PITSTOP_STATUS_UNSERVED = 0,

    // Mandatory pitstop served
    R3E_PITSTOP_STATUS_SERVED = 1,
} r3e_pitstop_status;

typedef enum
{
    // N/A
    R3E_FINISH_STATUS_UNAVAILABLE = -1,

    // Still on track, not finished
    R3E_FINISH_STATUS_NONE = 0,

    // Finished session normally
    R3E_FINISH_STATUS_FINISHED = 1,

    // Did not finish
    R3E_FINISH_STATUS_DNF = 2,

    // Did not qualify
    R3E_FINISH_STATUS_DNQ = 3,

    // Did not start
    R3E_FINISH_STATUS_DNS = 4,

    // Disqualified
    R3E_FINISH_STATUS_DQ = 5,
} r3e_finish_status;

typedef enum
{
    R3E_TIRE_TYPE_UNAVAILABLE = -1,
    R3E_TIRE_TYPE_OPTION = 0,
    R3E_TIRE_TYPE_PRIME = 1,
} r3e_tire_type;

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
} r3e_ori_f32;

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
} r3e_tire_temps;

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
} r3e_car_damage;

typedef struct
{
  r3e_float32 FrontLeft;
  r3e_float32 FrontRight;
  r3e_float32 RearLeft;
  r3e_float32 RearRight;
} r3e_tire_pressure;

typedef struct
{
  r3e_float32 FrontLeft;
  r3e_float32 FrontRight;
  r3e_float32 RearLeft;
  r3e_float32 RearRight;
} r3e_brake_temps;

typedef struct
{
  r3e_int32 DriveThrough;
  r3e_int32 StopAndGo;
  r3e_int32 PitStop;
  r3e_int32 TimeDeduction;
  r3e_int32 SlowDown;
} r3e_cut_track_penalties;

typedef struct
{
  r3e_float32 Sector1;
  r3e_float32 Sector2;
  r3e_float32 Sector3;
} r3e_sectors;

typedef struct
{
    r3e_float32 FrontLeft;
    r3e_float32 FrontRight;
    r3e_float32 RearLeft;
    r3e_float32 RearRight;
} r3e_tyre_dirt;

typedef struct
{
    r3e_float32 FrontLeft;
    r3e_float32 FrontRight;
    r3e_float32 RearLeft;
    r3e_float32 RearRight;
} r3e_wheel_speed;

typedef struct
{
    r3e_int32   TrackID;
    r3e_int32   LayoutID;
    r3e_float32 Length;
} r3e_track_info;

typedef struct
{
    r3e_u8char  Name[64];
    r3e_int32   CarNumber;
    r3e_int32   ClassID;
    r3e_int32   ModelID;
    r3e_int32   TeamID;
    r3e_int32   LiveryID;
    r3e_int32   ManufacturerID;
    r3e_int32   SlotID;
    r3e_int32   ClassPerformanceIndex;
} r3e_driver_info;

typedef struct
{
    r3e_int32 Available;
    r3e_int32 Engaged;
    r3e_int32 AmountLeft;
    r3e_float32 EngagedTimeLeft;
    r3e_float32 WaitTimeLeft;
} r3e_push_to_pass;

typedef struct
{
    r3e_driver_info   DriverInfo;
    r3e_int32         FinishStatus;
    r3e_int32         Place;
    r3e_float32       LapDistance;
    r3e_vec3_f32      Position;
    r3e_int32         TrackSector;
    r3e_int32         CompletedLaps;
    r3e_int32         CurrentLapValid;
    r3e_float32       LapTimeCurrentSelf;
    r3e_sectors       SectorTimeCurrentSelf;
    r3e_sectors       SectorTimePreviousSelf;
    r3e_sectors       SectorTimeRestSelf;
    r3e_float32       TimeDeltaFront;
    r3e_float32       TimeDeltaBehind;
    r3e_int32         PitstopStatus;
    r3e_int32         InPitlane;
    r3e_int32         NumPitstops;
    r3e_cut_track_penalties Penalties;
    r3e_float32       CarSpeed;
    r3e_int32         TireType;
} r3e_driver_data_1;
]]

local R3E_DEFS_PLAYER1 = 
[[
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
    r3e_tire_temps TireTemp;

    // Number of penalties pending for the player
    r3e_int32 NumPenalties;

    // Physical location of car's center of gravity in world space (X, Y, Z) (Y = up)
    r3e_vec3_f32 CarCgLoc;

    // Pitch, yaw, roll
    // Unit: Radians (rad)
    r3e_ori_f32 CarOrientation;

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
    
    // The current race event index, for championships with multiple events
    // Note: 0-indexed, -1 = N/A
    r3e_int32 EventIndex;

    // Which session the player is in (practice, qualifying, race, etc.)
    // Note: See the r3e_session enum
    r3e_int32 SessionType;

    // Which phase the current session is in (gridwalk, countdown, green flag, etc.)
    // Note: See the r3e_session_phase enum
    r3e_int32 SessionPhase;

    // The current iteration of the current type of session (second qualifying session, etc.)
    // Note: 0-indexed, -1 = N/A
    r3e_int32 SessionIteration;

    // Which controller is currently controlling the player's car (AI, player, remote, etc.)
    // Note: See the r3e_control enum
    r3e_int32 ControlType;

    // How pressed the throttle pedal is
    // Range: 0.0 - 1.0
    r3e_float32 ThrottlePedal;

    // How pressed the brake pedal is (-1.0 = N/A)
    // Range: 0.0 - 1.0
    r3e_float32 BrakePedal;

    // How pressed the clutch pedal is (-1.0 = N/A)
    // Range: 0.0 - 1.0
    r3e_float32 ClutchPedal;

    // How much the player's brakes are biased towards the back wheels (0.3 = 30%, etc.)
    // Note: -1.0 = N/A
    r3e_float32 BrakeBias;

    // Unit: Kilopascals (KPa)
    r3e_tire_pressure TirePressure;

    // -1 = no data available
    //  0 = not active
    //  1 = active
    r3e_int32 TireWearActive;

    // Which type of tires the player's car has (option, prime, etc.)
    // Note: See the r3e_tire_type enum
    r3e_int32 TireType;

    // Brake temperatures for all four wheels
    // Unit: Celsius (C)
    r3e_brake_temps BrakeTemperatures;

    // -1 = no data
    //  0 = not active
    //  1 = active
    r3e_int32 FuelUseActive;

    // Amount of time remaining for the current session
    // Note: Only available in time-based sessions, -1.0 = N/A
    // Units: Seconds
    r3e_float32 SessionTimeRemaining;

    // The current best lap time for the leader of the session (-1.0 = N/A)
    r3e_float32 LapTimeBestLeader;

    // The current best lap time for the leader of the player's class in the current session (-1.0 = N/A)
    r3e_float32 LapTimeBestLeaderClass;

    // Reserved for future (proper) implementation of lap_time_delta_self
    r3e_float32 _LapTimeDeltaSelf;

    // The time delta between the player's time and the leader of the current session (-1.0 = N/A)
    r3e_float32 LapTimeDeltaLeader;

    // The time delta between the player's time and the leader of the player's class in the current session (-1.0 = N/A)
    r3e_float32 _LapTimeDeltaLeaderClass;

    // Reserved for future (proper) implementation of sector_time_delta_self
    r3e_sectors _SectorTimeDeltaSelf;

    // Reserved for future (proper) implementation of sector_time_delta_leader
    r3e_sectors _SectorTimeDeltaLeader;

    // Reserved for future (proper) implementation of sector_time_delta_leader_class
    r3e_sectors SectorTimeDeltaLeaderClass;

    // Time delta between the player and the car placed in front (-1.0 = N/A)
    // Units: Seconds
    r3e_float32 TimeDeltaFront;

    // Time delta between the player and the car placed behind (-1.0 = N/A)
    // Units: Seconds
    r3e_float32 TimeDeltaBehind;

    // Current status of the pit stop
    // Note: See the R3E.Constant.PitWindow enum
    r3e_int32 PitWindowStatus;

    // The minute/lap into which you're allowed/obligated to pit
    // Unit: Minutes in time-based sessions, otherwise lap
    r3e_int32 PitWindowStart;

    // The minute/lap into which you can/should pit
    // Unit: Minutes in time based sessions, otherwise lap
    r3e_int32 PitWindowEnd;

    // Total number of cut track warnings
    r3e_int32 CutTrackWarnings;

    // The number of penalties the player currently has pending of each type (-1 = N/A)
    r3e_cut_track_penalties Penalties;

    // ...
    r3e_flags Flags;

    // ...
    r3e_car_damage CarDamage;
    
    // Slot ID for the currently active car
    r3e_int32 SlotID;

    // Amount of dirt built up per tyre
    // Range: 0.0 - 1.0
    r3e_tyre_dirt TyreDirt;

    // -1 = no data
    //  0 = not active
    //  1 = active
    r3e_int32 PitLimiter;

    // Wheel speed
    // Unit: Radians per second (rad/s)
    r3e_wheel_speed WheelSpeed;

    // Info about track and layout
    r3e_track_info TrackInfo;
    
    r3e_push_to_pass  PushToPass;
]]


local R3E_DEFS = R3E_DEFS_COMMON..[[

typedef struct { 

]]..R3E_DEFS_PLAYER1..[[

} r3e_shared;

typedef struct { 

]]..R3E_DEFS_PLAYER1..[[

    // Contains name and vehicle info for all drivers in place order
    r3e_driver_data_1 AllDriversData1[128];
} r3e_shared_full;
]]

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

local r3e_shared_type_full      = ffi.typeof("r3e_shared_full")
local r3e_shared_type_ptr_full  = ffi.typeof("r3e_shared_full*")
local r3e_shared_size_full      = ffi.sizeof("r3e_shared_full")

local r3e_shared_type           = ffi.typeof("r3e_shared")
local r3e_shared_type_ptr       = ffi.typeof("r3e_shared*")
local r3e_shared_size           = ffi.sizeof("r3e_shared")

print ("r3e sizeof shared",       r3e_shared_size)
print ("r3e sizeof shared full",  r3e_shared_size_full)

local _M = {
  RPS_TO_RPM = (60 / (2 * math.pi)),
  MPS_TO_KPH = 3.6,
  SHARED_TYPE = r3e_shared_type,
  SHARED_TYPE_NAME = "r3e_shared",
  SHARED_SIZE = r3e_shared_size,
  
  SHARED_TYPE_FULL = r3e_shared_type_full,
  SHARED_TYPE_NAME_FULL = "r3e_shared_full",
  SHARED_SIZE_FULL = r3e_shared_size_full,
  
  DEFS = R3E_DEFS,
  DEFS_FULL = R3E_DEFS_FULL,
  
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
  
  FinishStatus = {
    Unavailable = -1,
    None = 0,
    Finished = 1,
    DNF = 2,
    DNQ = 3,
    DNS = 4,
    DQ = 5,
  },
  
  PitstopStatus = {
    Unavailable = -1,
    Unserved = 0,
    Served = 1,
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
        r3e_shared_size_full,
        R3E_SHARED_MEMORY_NAME);
end

function _M.isMappable()
  local handle = open()
  if (handle ~= nil) then
    ffi.C.CloseHandle(handle)
  end
  return handle ~= nil
end

function _M.createMapping(writeonly, fulldata)
  assert(not writeonly or (writeonly and fulldata), "writeonly mappings must be using fulldata")
    
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
  
  local buffer = ffi.C.MapViewOfFile(handle, filemap, 0, 0, r3e_shared_size_full)
  buffer = ffi.cast(r3e_shared_type_ptr_full, buffer)
  if (buffer == nil) then
    error("could not map buffer: "..ffi.C.GetLastError())
    ffi.C.CloseHandle(handle)
    return
  end
  
 
  local map = {}
  print("r3edata map created", map, writeonly)
  
  if (fulldata) then
    if (writeonly) then
      function map:writeData(src)
        ffi.copy(buffer, src, r3e_shared_size_full)
      end
    else
      function map:readData(dst)
        ffi.copy(dst, buffer, r3e_shared_size_full)
      end
    end
  else
    -- transcode from full/reduced
    assert(not writeonly)
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


