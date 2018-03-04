local ffi = require "ffi"

local R3E_FULL_DRIVERS = R3E_FULL_DRIVERS or 128
local R3E_SHARED_MEMORY_NAME = "$R3E"

local R3E_DEFS_COMMON = [[
  
typedef int32_t r3e_int32;
typedef float r3e_float32;
typedef double r3e_float64;
typedef uint8_t r3e_u8char;
  
#pragma pack(1)

typedef enum
{
    // Major version number to test against
    R3E_VERSION_MAJOR = 1,
    // Minor version number to test against
    R3E_VERSION_MINOR = 7,
    R3E_NUM_DRIVERS_MAX = 128,
}r3e_misc;

typedef enum
{
    R3E_SESSION_UNAVAILABLE = -1,
    R3E_SESSION_PRACTICE = 0,
    R3E_SESSION_QUALIFY = 1,
    R3E_SESSION_RACE = 2,
    R3E_SESSION_WARMUP = 3,
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
    R3E_TIRE_TYPE_UNAVAILABLE = -1,
    R3E_TIRE_TYPE_OPTION = 0,
    R3E_TIRE_TYPE_PRIME = 1,
} r3e_tire_type;

typedef enum
{
    R3E_TIRE_SUBTYPE_UNAVAILABLE = -1,
    R3E_TIRE_SUBTYPE_PRIMARY = 0,
    R3E_TIRE_SUBTYPE_ALTERNATE = 1,
    R3E_TIRE_SUBTYPE_SOFT = 2,
    R3E_TIRE_SUBTYPE_MEDIUM = 3,
    R3E_TIRE_SUBTYPE_HARD = 4,
} r3e_tire_subtype;

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
    // N/A
    R3E_SESSION_LENGTH_UNAVAILABLE = -1,

    R3E_SESSION_LENGTH_TIME_BASED = 0,

    R3E_SESSION_LENGTH_LAP_BASED = 1,

    // Time and lap based session means there will be an extra lap after the time has run out
    R3E_SESSION_LENGTH_TIME_AND_LAP_BASED = 2,
} r3e_session_length_format;

typedef struct
{
    r3e_float32 x;
    r3e_float32 y;
    r3e_float32 z;
} r3e_vec3_f32;

typedef struct
{
    r3e_float64 x;
    r3e_float64 y;
    r3e_float64 z;
} r3e_vec3_f64;

typedef struct
{
    r3e_float32 pitch;
    r3e_float32 yaw;
    r3e_float32 roll;
} r3e_ori_f32;

typedef struct
{
    r3e_float32 front_left_left;
    r3e_float32 front_left_center;
    r3e_float32 front_left_right;
    r3e_float32 front_right_left;
    r3e_float32 front_right_center;
    r3e_float32 front_right_right;
    r3e_float32 rear_left_left;
    r3e_float32 rear_left_center;
    r3e_float32 rear_left_right;
    r3e_float32 rear_right_left;
    r3e_float32 rear_right_center;
    r3e_float32 rear_right_right;
} r3e_tire_temp;

// High precision data for player's vehicle only
typedef struct
{
    // Virtual physics time
    // Unit: Ticks (1 tick = 1/400th of a second)
    r3e_int32 game_simulation_ticks;

    // Virtual physics time
    // Unit: Seconds
    r3e_float64 game_simulation_time;

    // Car world-space position
    r3e_vec3_f64 position;

    // Car world-space velocity
    // Unit: Meter per second (m/s)
    r3e_vec3_f64 velocity;

    // Car local-space velocity
    // Unit: Meter per second (m/s)
    r3e_vec3_f64 local_velocity;

    // Car world-space acceleration
    // Unit: Meter per second squared (m/s^2)
    r3e_vec3_f64 acceleration;

    // Car local-space acceleration
    // Unit: Meter per second squared (m/s^2)
    r3e_vec3_f64 local_acceleration;

    // Car body orientation
    // Unit: Euler angles
    r3e_vec3_f64 orientation;

    // Car body rotation
    r3e_vec3_f64 rotation;

    // Car body angular acceleration (torque divided by inertia)
    r3e_vec3_f64 angular_acceleration;

    // Car world-space angular velocity
    // Unit: Radians per second
    r3e_vec3_f64 angular_velocity;

    // Car local-space angular velocity
    // Unit: Radians per second
    r3e_vec3_f64 local_angular_velocity;
} r3e_playerdata;

typedef struct
{
    // Whether yellow flag is currently active
    // -1 = no data
    //  0 = not active
    //  1 = active
    r3e_int32 yellow;

    // Whether blue flag is currently active
    // -1 = no data
    //  0 = not active
    //  1 = active
    r3e_int32 blue;

    // Whether black flag is currently active
    // -1 = no data
    //  0 = not active
    //  1 = active
    r3e_int32 black;
} r3e_flags;

typedef struct
{
    // Whether green flag is currently active
    // -1 = no data
    //  0 = not active
    //  1 = active
    r3e_int32 green;

    // Whether checkered flag is currently active
    // -1 = no data
    //  0 = not active
    //  1 = active
    r3e_int32 checkered;

    // Whether black and white flag is currently active and reason
    // -1 = no data
    //  0 = not active
    //  1 = blue flag 1st warning
    //  2 = blue flag 2nd warning
    //  3 = wrong way
    //  4 = cutting track
    r3e_int32 black_and_white;
} r3e_flags_extended;

typedef struct
{
    // Whether white flag is currently active
    // -1 = no data
    //  0 = not active
    //  1 = active
    r3e_int32 white;

    // Whether yellow flag was caused by current slot
    // -1 = no data
    //  0 = didn't cause it
    //  1 = caused it
    r3e_int32 yellowCausedIt;

    // Whether overtake of car in front by current slot is allowed under yellow flag
    // -1 = no data
    //  0 = not allowed
    //  1 = allowed
    r3e_int32 yellowOvertake;

    // Whether you have gained positions illegaly under yellow flag to give back
    // -1 = no data
    //  0 = no positions gained
    //  n = number of positions gained
    r3e_int32 yellowPositionsGained;
} r3e_flags_extended_2;

typedef struct
{
    // Range: 0.0 - 1.0
    // Note: -1.0 = N/A
    r3e_float32 engine;

    // Range: 0.0 - 1.0
    // Note: -1.0 = N/A
    r3e_float32 transmission;

    // Range: 0.0 - 1.0
    // Note: A bit arbitrary at the moment. 0.0 doesn't necessarily mean completely destroyed.
    // Note: -1.0 = N/A
    r3e_float32 aerodynamics;
} r3e_car_damage;

typedef struct
{
    r3e_float32 front_left;
    r3e_float32 front_right;
    r3e_float32 rear_left;
    r3e_float32 rear_right;
} r3e_tire_data;

typedef struct
{
    r3e_int32 drive_through;
    r3e_int32 stop_and_go;
    r3e_int32 pit_stop;
    r3e_int32 time_deduction;
    r3e_int32 slow_down;
} r3e_cut_track_penalties;

typedef struct
{
    // If DRS is equipped and allowed
    // 0 = No, 1 = Yes, -1 = N/A
    r3e_int32 equipped;
    // Got DRS activation left
    // 0 = No, 1 = Yes, -1 = N/A
    r3e_int32 available;
    // Number of DRS activations left this lap
    // Note: In sessions with 'endless' amount of drs activations per lap this value starts at int32::max
    // -1 = N/A
    r3e_int32 numActivationsLeft;
    // DRS engaged
    // 0 = No, 1 = Yes, -1 = N/A
    r3e_int32 engaged;
} r3e_drs;

typedef struct
{
    r3e_int32 available;
    r3e_int32 engaged;
    r3e_int32 amount_left;
    r3e_float32 engaged_time_left;
    r3e_float32 wait_time_left;
} r3e_push_to_pass;

typedef struct
{
    r3e_float32 sector1;
    r3e_float32 sector2;
    r3e_float32 sector3;
} r3e_sectors;

typedef struct
{
    r3e_u8char name[64];
    r3e_int32 car_number;
    r3e_int32 class_id;
    r3e_int32 model_id;
    r3e_int32 team_id;
    r3e_int32 livery_id;
    r3e_int32 manufacturer_id;
    r3e_int32 slot_id;
    r3e_int32 class_performance_index;
} r3e_driver_info;

typedef struct
{
    r3e_driver_info driver_info;
    r3e_finish_status finish_status;
    r3e_int32 place;
    r3e_float32 lap_distance;
    r3e_vec3_f32 position;
    r3e_int32 track_sector;
    r3e_int32 completed_laps;
    r3e_int32 current_lap_valid;
    r3e_float32 lap_time_current_self;
    r3e_sectors sector_time_current_self;
    r3e_sectors sector_time_previous_self;
    r3e_sectors sector_time_best_self;
    r3e_float32 time_delta_front;
    r3e_float32 time_delta_behind;
    r3e_pitstop_status pitstop_status;
    r3e_int32 in_pitlane;
    r3e_int32 num_pitstops;
    r3e_cut_track_penalties penalties;
    r3e_float32 car_speed;
    r3e_int32 tire_type_front;
    r3e_int32 tire_type_rear;
    r3e_int32 tire_subtype_front;
    r3e_int32 tire_subtype_rear;
} r3e_driver_data;
]]

local R3E_DEFS_PLAYER1 = 
[[
    //////////////////////////////////////////////////////////////////////////
    // Version
    //////////////////////////////////////////////////////////////////////////

    r3e_int32 _version_major;
    r3e_int32 _version_minor;
    r3e_int32 _all_drivers_offset; // Offset to num_cars
    r3e_int32 _driver_data_size; // size of the driver data struct

    //////////////////////////////////////////////////////////////////////////
    // Game State
    //////////////////////////////////////////////////////////////////////////

    r3e_int32 game_paused;
    r3e_int32 game_in_menus;

    //////////////////////////////////////////////////////////////////////////
    // High detail
    //////////////////////////////////////////////////////////////////////////

    // High detail player vehicle data
    r3e_playerdata player;

    //////////////////////////////////////////////////////////////////////////
    // Event and session
    //////////////////////////////////////////////////////////////////////////

    r3e_u8char track_name[64];
    r3e_u8char layout_name[64];

    r3e_int32 track_id;
    r3e_int32 layout_id;
    r3e_float32 layout_length;

    // The current race event index, for championships with multiple events
    // Note: 0-indexed, -1 = N/A
    r3e_int32 event_index;
    // Which session the player is in (practice, qualifying, race, etc.)
    // Note: See the r3e_session enum
    r3e_int32 session_type;
    // The current iteration of the current type of session (second qualifying session, etc.)
    // Note: 0-indexed, -1 = N/A
    r3e_int32 session_iteration;

    // Which phase the current session is in (gridwalk, countdown, green flag, etc.)
    // Note: See the r3e_session_phase enum
    r3e_int32 session_phase;

    // If tire wear is active (-1 = N/A, 0 = Off, 1 = 1)
    r3e_int32 tire_wear_active;
    // If fuel usage is active (-1 = N/A, 0 = Off, 1 = 1)
    r3e_int32 fuel_use_active;

    // Total number of laps in the race, or -1 if player is not in race mode (practice, test mode, etc.)
    r3e_int32 number_of_laps;

    // Amount of time remaining for the current session
    // Note: Only available in time-based sessions, -1.0 = N/A
    // Units: Seconds
    r3e_float32 session_time_remaining;

    //////////////////////////////////////////////////////////////////////////
    // Pit
    //////////////////////////////////////////////////////////////////////////

    // Current status of the pit stop
    // Note: See the r3e_pit_window enum
    r3e_int32 pit_window_status;

    // The minute/lap from which you're obligated to pit (-1 = N/A)
    // Unit: Minutes in time-based sessions, otherwise lap
    r3e_int32 pit_window_start;

    // The minute/lap into which you need to have pitted (-1 = N/A)
    // Unit: Minutes in time-based sessions, otherwise lap
    r3e_int32 pit_window_end;

    // If current vehicle is in pitlane (-1 = N/A)
    r3e_int32 in_pitlane;

    // Number of pitstops the current vehicle has performed (-1 = N/A)
    r3e_int32 num_pitstops;

    //////////////////////////////////////////////////////////////////////////
    // Scoring & Timings
    //////////////////////////////////////////////////////////////////////////

    // The current state of each type of flag
    r3e_flags flags;

    // Current position (1 = first place)
    r3e_int32 position;

    r3e_finish_status finish_status;

    // Total number of cut track warnings (-1 = N/A)
    r3e_int32 cut_track_warnings;
    // The number of penalties the car currently has pending of each type (-1 = N/A)
    r3e_cut_track_penalties penalties;
    // Total number of penalties pending for the car
    // Note: See the 'penalties' field
    r3e_int32 num_penalties;

    // How many laps the car has completed. If this value is 6, the car is on it's 7th lap. -1 = n/a
    r3e_int32 completed_laps;
    r3e_int32 current_lap_valid;
    r3e_int32 track_sector;
    r3e_float32 lap_distance;
    // fraction of lap completed, 0.0-1.0, -1.0 = N/A
    r3e_float32 lap_distance_fraction;

    // The current best lap time for the leader of the session
    // Unit: Seconds (-1.0 = N/A)
    r3e_float32 lap_time_best_leader;
    // The current best lap time for the leader of the current/viewed vehicle's class in the current session
    // Unit: Seconds (-1.0 = N/A)
    r3e_float32 lap_time_best_leader_class;
    // Sector times of fastest lap by anyone in session
    // Unit: Seconds (-1.0 = N/A)
    r3e_sectors session_best_lap_sector_times;
    // Best lap time
    // Unit: Seconds (-1.0 = N/A)
    r3e_float32 lap_time_best_self;
    r3e_sectors sector_time_best_self;
    // Previous lap
    // Unit: Seconds (-1.0 = N/A)
    r3e_float32 lap_time_previous_self;
    r3e_sectors sector_time_previous_self;
    // Current lap time
    // Unit: Seconds (-1.0 = N/A)
    r3e_float32 lap_time_current_self;
    r3e_sectors sector_time_current_self;
    // The time delta between this car's time and the leader
    // Unit: Seconds (-1.0 = N/A)
    r3e_float32 lap_time_delta_leader;
    // The time delta between this car's time and the leader of the car's class
    // Unit: Seconds (-1.0 = N/A)
    r3e_float32 lap_time_delta_leader_class;
    // Time delta between this car and the car placed in front
    // Unit: Seconds (-1.0 = N/A)
    r3e_float32 time_delta_front;
    // Time delta between this car and the car placed behind
    // Unit: Seconds (-1.0 = N/A)
    r3e_float32 time_delta_behind;

    //////////////////////////////////////////////////////////////////////////
    // Vehicle information
    //////////////////////////////////////////////////////////////////////////

    r3e_driver_info vehicle_info;
    r3e_u8char player_name[64];

    //////////////////////////////////////////////////////////////////////////
    // Vehicle state
    //////////////////////////////////////////////////////////////////////////

    // Which controller is currently controlling the vehicle (AI, player, remote, etc.)
    // Note: See the r3e_control enum
    r3e_int32 control_type;

    // Unit: Meter per second (m/s)
    r3e_float32 car_speed;

    // Unit: Radians per second (rad/s)
    r3e_float32 engine_rps;
    r3e_float32 max_engine_rps;

    // -2 = N/A, -1 = reverse, 0 = neutral, 1 = first gear, ...
    r3e_int32 gear;
    // -1 = N/A
    r3e_int32 num_gears;

    // Physical location of car's center of gravity in world space (X, Y, Z) (Y = up)
    r3e_vec3_f32 car_cg_location;
    // Pitch, yaw, roll
    // Unit: Radians (rad)
    r3e_ori_f32 car_orientation;
    // Acceleration in three axes (X, Y, Z) of car body in local-space.
    // From car center, +X=left, +Y=up, +Z=back.
    // Unit: Meter per second squared (m/s^2)
    r3e_vec3_f32 local_acceleration;

    // Unit: Liters (l)
    // Note: Not valid for AI or remote players
    r3e_float32 fuel_left;
    r3e_float32 fuel_capacity;
    // Unit: Celsius (C)
    // Note: Not valid for AI or remote players
    r3e_float32 engine_water_temp;
    r3e_float32 engine_oil_temp;
    // Unit: Kilopascals (KPa)
    // Note: Not valid for AI or remote players
    r3e_float32 fuel_pressure;
    // Unit: Kilopascals (KPa)
    // Note: Not valid for AI or remote players
    r3e_float32 engine_oil_pressure;

    // How pressed the throttle pedal is 
    // Range: 0.0 - 1.0 (-1.0 = N/A)
    // Note: Not valid for AI or remote players
    r3e_float32 throttle_pedal;
    // How pressed the brake pedal is
    // Range: 0.0 - 1.0 (-1.0 = N/A)
    // Note: Not valid for AI or remote players
    r3e_float32 brake_pedal;
    // How pressed the clutch pedal is 
    // Range: 0.0 - 1.0 (-1.0 = N/A)
    // Note: Not valid for AI or remote players
    r3e_float32 clutch_pedal;

    // DRS data
    r3e_drs drs;

    // Pit limiter (-1 = N/A, 0 = inactive, 1 = active)
    r3e_int32 pit_limiter;

    // Push to pass data
    r3e_push_to_pass push_to_pass;

    // How much the vehicle's brakes are biased towards the back wheels (0.3 = 30%, etc.) (-1.0 = N/A)
    // Note: Not valid for AI or remote players
    r3e_float32 brake_bias;

    //////////////////////////////////////////////////////////////////////////
    // Tires
    //////////////////////////////////////////////////////////////////////////

    // Which type of tires the car has (option, prime, etc.)
    // Note: See the r3e_tire_type enum, deprecated - use the values further down instead
    r3e_int32 tire_type;
    // Rotation speed
    // Uint: Radians per second
    r3e_tire_data tire_rps;
    // Range: 0.0 - 1.0 (-1.0 = N/A)
    r3e_tire_data tire_grip;
    // Range: 0.0 - 1.0 (-1.0 = N/A)
    r3e_tire_data tire_wear;
    // Unit: Kilopascals (KPa) (-1.0 = N/A)
    // Note: Not valid for AI or remote players
    r3e_tire_data tire_pressure;
    // Percentage of dirt on tire (-1.0 = N/A)
    // Range: 0.0 - 1.0
    r3e_tire_data tire_dirt;
    // Brake temperature (-1.0 = N/A)
    // Unit: Celsius (C)
    // Note: Not valid for AI or remote players
    r3e_tire_data brake_temp;
    // Temperature of three points across the tread of the tire (-1.0 = N/A)
    // Unit: Celsius (C)
    // Note: Not valid for AI or remote players
    r3e_tire_temp   tire_temp;
    // Which type of tires the car has (option, prime, etc.)
    // Note: See the r3e_tire_type enum
    r3e_int32 tire_type_front;
    r3e_int32 tire_type_rear;
    // Which subtype of tires the car has
    // Note: See the r3e_tire_subtype enum
    r3e_int32 tire_subtype_front;
    r3e_int32 tire_subtype_rear;

    //////////////////////////////////////////////////////////////////////////
    // Damage
    //////////////////////////////////////////////////////////////////////////

    // The current state of various parts of the car
    // Note: Not valid for AI or remote players
    r3e_car_damage car_damage;

    //////////////////////////////////////////////////////////////////////////
    // Additional Info
    //////////////////////////////////////////////////////////////////////////

    // The current state of each type of extended flag
    r3e_flags_extended flags_extended;

    // Yellow flag for each sector; -1 = no data, 0 = not active, 1 = active
    r3e_int32 sector_yellow[3];

    // Distance into track for closest yellow, -1.0 if no yellow flag exists
    // Unit: Meters (m)
    r3e_float32 closest_yellow_distance_into_track;

    // Additional flag info
    r3e_flags_extended_2 flags_extended_2;

    // If the session is time based, lap based or time based with an extra lap at the end
    r3e_session_length_format session_length_format;
]]


local R3E_DEFS = R3E_DEFS_COMMON..[[

typedef struct { 

]]..R3E_DEFS_PLAYER1..[[

} r3e_shared;

typedef struct { 

]]..R3E_DEFS_PLAYER1..[[

    // Driver info
    //////////////////////////////////////////////////////////////////////////

    // Number of cars (including the player) in the race
    r3e_int32 num_cars;
    // Contains name and vehicle info for all drivers in place order
    r3e_driver_data all_drivers_data_1[]]..R3E_FULL_DRIVERS..[[];
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
      Race = 2,
      WarmUp = 3,
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
  return _M.emulation or isProcessRunning("RRRE64.exe")
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


