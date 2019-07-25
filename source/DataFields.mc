using Toybox.WatchUi as Ui;
using Toybox.Time as Time;
using Toybox.Time.Gregorian as Gregorian;
using Toybox.Lang as Lang;
using Toybox.System as System;
using Toybox.Timer as Timer;
using Toybox.Position as Position;
using Toybox.Attention as Attention;
using Toybox.Communications as Comm;

class DataField 
{
    var labelText;
    var unitsText;

    function initialize(label, units)
    {
        self.labelText = label;
        self.unitsText = units;
    }
    
    function value()
    {
        return "";
    }

    function label()
    {
        return labelText;
    }

    function units()
    {
        return unitsText;
    }
}

class DataFieldWithSet extends DataField
{
    var v;

    function initialize(label, units)
    {
        DataField.initialize(label, units);
    }

    function value()
    {
        return self.v;
    }

    function setValue(v)
    {
        self.v = v;
    }
}

class TimeField extends DataField
{
    function initialize()
    {
        return DataField.initialize("clk", "");
    }
    
    function value()
    {
        var now = Time.now();
        var timestruct = Gregorian.info(now, Time.FORMAT_SHORT);
        var clockTime = timestruct.hour.format("%02u") + ":" + timestruct.min.format("%02u");
    }
}

class TimerField extends DataFieldWithSet
{
    function initialize()
    {
        return DataFieldWithSet.initialize("tmr", "");
    }
}

class SogField extends DataField
{
    function initialize()
    {
        return DataField.initialize("sog", "kts");
    }
    
    function value()
    {
        var knots = $.speed * 1.94384449;
        var speedText = knots.format("%02.1f");
        return speedText;
    }
}

class CogField extends DataField
{
    function initialize()
    {
        return DataField.initialize("cog", "deg");
    }

    function value()
    {
        var headingText = ($.heading * 57.2957795);
        if (headingText < 0) { headingText += 360; }
        return headingText.format("%02.0f");
    }
}

class DtwField extends DataFieldWithSet
{
    function initialize()
    {
        return DataFieldWithSet.initialize("dtw", "nm");
    }
}

class BtwField extends DataFieldWithSet
{
    function initialize()
    {
        return DataFieldWithSet.initialize("btw", "deg");
    }
}

class VmgField extends DataFieldWithSet
{
    function initialize()
    {
        return DataFieldWithSet.initialize("vmg", "kts");
    }
}

// order must match
var fields = 
[
    new TimeField(),
    new TimerField(),
    new CogField(),
    new SogField(),
    new DtwField(),
    new BtwField(),
    new VmgField()
];

// order must match
const TIME_FIELD = 0;
const TIMER_FIELD = 1;
const COG_FIELD = 2;
const SOG_FIELD = 3;
const DTW_FIELD = 4;
const BTW_FIELD = 5;
const VMG_FILED = 6;
const MAX_FIELDS = 7;
