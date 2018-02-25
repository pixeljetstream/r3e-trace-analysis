

-- approximative delay in milliseconds, 10 is about 100x per second
-- each sample costs ~ 600-700 bytes
record.pollrate = 10 

-- For app developers set this to false, otherwise
-- only driving frames will be recorded (no AI, formation, in-menu... frames).
-- When active the trace file's times will be based on Player.GameSimulationTime,
-- otherwise based on recording time
record.onlydriving = true 

-- if onlydriving is active, we save when the game is being paused
-- useful for analysis while game is running
record.saveonpause = false

-- removes the "all driver" data, reducing the filesize a lot
-- this option set to false is preferred for telemetry usage
-- "true" is meant for debugging other tools
record.fulldata = false

-------------------------------------------

-- time delay in milliseconds
-- used if set, otherwise defaults to half of recorded average rate
replay.playrate = nil

-- play back based on time, otherwise frames
replay.timebased = true

-- dump full state every N seconds
replay.dumpinterval = 2

-- dump full state every N frames
replay.dumpframes = 120

-- if not set all properties are dumped
-- otherwise use strings like {"player.game_simulation_time",}
replay.dumpfilter = nil

-- playback speed (frames or time are multiplied by this)
replay.playspeed = 1

-------------------------------------------
-- if not set all properties are shown
-- otherwise use string array like {"player.game_simulation_time",}
viewer.propertyfilter = nil

-- for export and plots, sample at this resolution (seconds)
viewer.samplerate = 0.1

-- multisampling level
viewer.msaa = 8

-- remove label during animation
viewer.animationremoveslabel = false

-- use conversions (m/s to km/h, radians to degress)
viewer.convertvalues = true

-- run viewer in fulldata mode, this allows loading fulldata traces, 
-- otherwise they will be rejected
viewer.fulldata = false
