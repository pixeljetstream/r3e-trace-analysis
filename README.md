r3e-trace-analysis
==================

Tools to record, replay and inspect shared memory of [R3E](http://game.raceroom.com).
The project is not supported nor in anyway endorsed by the creators of R3E.

© 2015 by Christoph Kubisch, 

### **r3e-trace-record.exe**

Records all [shared memory](https://github.com/sector3studios/r3e-api) data of every session while the game is running (~15 ms pollrate) to a new file (e.g. "trace_151107_1750.r3t" ).
Start before running R3E, the tool terminates itself after R3E was closed.

### **RRRE.exe** 

Allows you to replay a trace, useful for debugging tools that also make use of the shared memory
bridge of R3E

* Currently the replay rate is ~15 milliseconds
* All float values are linearly interpolated

### **r3e-trace-viewer.exe**

TODO, a tool to open a trace file and inspect all data, as well as visualize data based on the players recorded position (poor man's telemetry). Will allow to browse through individual laps recorded within the session.

### Caveats

The Lua implemention of record and replay may be replaced by native C/C++ code to allow for greater sampling and playback rates.