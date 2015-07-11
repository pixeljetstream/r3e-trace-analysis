r3e-trace-analysis
==================

Tools to record, replay and inspect shared memory of [R3E](http://game.raceroom.com)
© 2015 by Christoph Kubisch

## **r3e-trace-record.exe**

Records every R3E session while the game is running (~15 ms pollrate).

## **RRRE.exe** 

Allows you to replay a trace, useful for debugging tools that also make use of the shared memory
bridge of R3E

* Currently the replay rate is ~15 ms
* For now only Player.GameSimulationTime is interpolated

## **r3e-trace-viewer.exe**

TODO, a tool to open a trace file and inspect all data, as well as visualize data based on the players recorded position (poor man's telemetry).
