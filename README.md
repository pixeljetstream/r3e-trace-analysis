r3e-trace-analysis
==================

Tools to record, replay and inspect shared memory of [R3E](http://game.raceroom.com).
The project is not supported nor in anyway endorsed by the creators of R3E.

© 2015 by Christoph Kubisch, 

### **r3e-trace-record.exe**

Records all [shared memory](https://github.com/sector3studios/r3e-api) data of every session while the game is running (~10 ms pollrate) to a new file (e.g. "trace_151107_1750.r3t" ).
Start before running R3E, the tool terminates itself after R3E was closed.

Allows recording of the full session (for app developers), or only frames when driving (intended for telemetry analysis). 

### **RRRE.exe** 

Allows you to replay a trace, useful for debugging tools that also make use of the shared memory
bridge of R3E. Frame- or time-based replaying is supported. The state values get interpolated.

* Currently the replay rate is ~10 milliseconds
* All float values are linearly interpolated

### **r3e-trace-viewer.exe**

![ui](https://github.com/pixeljetstream/r3e-trace-analysis/blob/master/doc/ui.png)

A tool to open a trace file and inspect all data. Allows to browse through individual laps recorded within the session. Double-click a lap to make it active. Laps with "invalid" times (shortcuts...) are in brackets "()". The current selected lap is marked with "|||".

The current lap will be rendered in the track-view. The first valid lap of a file is drawn as fine line on top, as well as a marker with the current position.

Use the selectors (A,B,C,D) to compare different values or laps. A selector change will not
cause any redraw, only selecting a lap or property will. With the "Animated driving line" feature 
you can improve the perception of the stippled driving lines.

![track_animated](https://github.com/pixeljetstream/r3e-trace-analysis/blob/master/doc/track_animated.gif)

When double-clicking a single property it is printed in the track view. The current "Gradient" setting is applied, see explanation further down. It allows to visualize up- or down shifts for example.

![track_gradient](https://github.com/pixeljetstream/r3e-trace-analysis/blob/master/doc/track_gradient.png)

Using the "Range" button, you can select to visualize a sub-range of the track. All plots will get cut
by the duration the fastest plot took. For example in this image you can see we lost a lot of time in the beginning of the track in lap 4 (lap 4's left side vs. lap 5's right side).

![track_range](https://github.com/pixeljetstream/r3e-trace-analysis/blob/master/doc/track_range.png)

However when start our analysis after the troubled section we an see that both laps ended up pretty similar in duration.

![track_range_detail](https://github.com/pixeljetstream/r3e-trace-analysis/blob/master/doc/track_range_detail.png)

You can select interesting properties and export the current lap's interpolated values using the export button and create diagrams in your favorite chart software. How many sample points are taken is influenced by ```config.viewer.samplerate```.

![csvexport](https://github.com/pixeljetstream/r3e-trace-analysis/blob/master/doc/csvexport.png)

By modifying the "Gradient" value to greater 0, you can export the rate of change of values.
Positive values means the properties increased in the given gradient time span ( ```time +/- gradient * config.viewer.samplerate / 2```). 

![csvexport_gradient](https://github.com/pixeljetstream/r3e-trace-analysis/blob/master/doc/csvexport_gradient.png)


TODO:

* Zoom and pan

### Settings

The default settings are stored in "config.lua". Create "config-user.lua" to override those.

### History
* 26.07.2015:
 * Range option to compare limited sections of the track and their effect on time
* 25.07.2015:
 * Animated driving line
 * lap comparison via selector api
 * GLSL used for rendering, 8x msaa default
* 19.07.2015:
 * track view
 * csv file export
* 18.07.2015:
 * first version of trace viewer working
* 12.07.2015:
 * major revision in fileformat
 * improved detection of session begin/end
 * improved lap markers
 * allow "only driving" recordings, that filter away frames in game menu or driven by AI
* 11.07.2015: 
 * initial release

### Caveats

The Lua implemention of record and should be replaced by native C/C++ code to allow for greater sampling and playback rates. This is currently not a primary goal, as only few apps need high frequency data.

