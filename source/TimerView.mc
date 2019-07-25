using Toybox.WatchUi as Ui;
using Toybox.Time as Time;
using Toybox.Time.Gregorian as Gregorian;
using Toybox.Lang as Lang;
using Toybox.System as System;
using Toybox.Timer as Timer;
using Toybox.Position as Position;
using Toybox.Attention as Attention;
using Toybox.ActivityRecording as Record;
using Toybox.Application as App;

//
// This screen can be in one of four modes, they each render through a different
// layout and have different behaviors.
//
// In general the user moves forward through these modes, and on reset goes 
// back to mode_prep.  The one exception is that they can clear finish times and
// go from mode_finish back to mode_sailing.
//
enum {
    mode_prep,              // default mode, not yet recording
    mode_insequence,        // in start sequence
    mode_sailing,           // racing or sailing has started
    mode_finish             // in finish mode, showing finish times
}

var timer = null;

class TimerView extends CommonView {
    // current mode
    var mode = mode_prep;
    // current mode view
    var modeView = mode_prep;
    // timerZero is when the timer will display 00:00.  If it is null
    // then no timer is running (we're in "Prep").  If (now - timerZero)
    // is positive then the timer is counting up and we're racing.  If 
    // it is negative then the timer is counting down and we're 
    // in start sequence.
    var timerZero;
    // how long should the timer be set to when the timer is reset?
    var timerDuration = 300;
    // one quarter of the screen in pixels 
    var quarterWidth;
    // the font that we use when drawing buttons

    var finishTimes = null;
    var raceTime = null;

    // remember when we last vibrated the watch, we do this to make sure that we don't vibrate
    // multiple times in the same second
    var lastVibrationDuration = 0;

    // field information
    var timerFields = new[3];

    //
    // initialize the view
    //
    function initialize() {
        $.timer = self;
        highSpeedRefresh = true;
        changeMode(self.mode);
        CommonView.initialize("timer");
    }

    //
    // Start the timer (occurs on enter button press).  This also 
    // starts recording a session (as soon as we have GPS).
    //
    // timerDuration -- How long to count down for
    //
    function startTimer(timerDuration) {
        System.println("starting new timer");
        timerZero = Time.now();
        timerZero = timerZero.add(new Time.Duration(timerDuration));
        changeMode(mode_insequence);
    }

    // 
    // change the mode of the timer view
    //
    function changeMode(newMode)
    {
        mode = newMode;
        updateFields();
    }

    function updateFields()
    {
        // read our settings
        var app = App.getApp();
        var timerDisplayMode = app.getProperty("timerDisplayMode");
        var bigTimer = (timerDisplayMode != null && timerDisplayMode == 1);
        var autoSwitchToMarks = app.getProperty("autoSwitchToMarks");

        // switch to marks view on race start
        if (mode == mode_sailing && autoSwitchToMarks)
        {
            $.inputDelegate.switchToView(:marksView);
        }

        if (bigTimer)
        {
            self.timerFields[0] = $.fields[TIMER_FIELD];
            self.timerFields[1] = $.fields[SOG_FIELD];
            self.timerFields[2] = $.fields[COG_FIELD];
        }
        else /* big COG (default) */
        {
            if (mode == mode_prep || mode == mode_insequence)
            {
                self.timerFields[0] = $.fields[TIMER_FIELD];
                self.timerFields[1] = $.fields[COG_FIELD];
                self.timerFields[2] = $.fields[SOG_FIELD];
            }
            else
            {
                self.timerFields[0] = $.fields[SOG_FIELD];
                self.timerFields[1] = $.fields[COG_FIELD];
                self.timerFields[2] = $.fields[TIMER_FIELD];
            }
        }
    }

    //
    // called when we need to sync to the nearest minute
    // this modifies timerZero
    //
    // syncUp -- true to go up a minute, false to go down a minute
    //
    function sync(syncUp)
    {
        var now = Time.now();
        var duration = now.subtract(timerZero);
        var seconds = duration.value();
        var minutes = seconds / 60;
        seconds = seconds % 60;
        timerZero = now;
        if (syncUp) {
            timerZero = timerZero.add(new Time.Duration((minutes + 1) * 60));
        } else {
            timerZero = timerZero.add(new Time.Duration((minutes) * 60));
        }
    }

    //
    // Ask if the user wants to reset, do the reset if they confirm
    //
    function promptReset() { 
        var dialog = new Ui.Confirmation("Confirm reset?");
        Ui.pushView(dialog, new ConfirmResetDelegate(), Ui.SLIDE_IMMEDIATE);
    }

    //
    // reset the timer.  This also stops recording a session.
    //
    function reset()
    {
        clearFinish();
        timerZero = null;
        changeMode(mode_prep);
    }

    //
    // Callback for clear finish button (only in mode_finish)
    //
    function clearFinish()
    {
        finishTimes = null;
        raceTime = null;
        changeMode(mode_sailing);
    }

    //
    // Callback for just sail button (in mode_prep, allows jumping right to
    // mode_sailing)
    //
    function justSail()
    {
        timerDuration = 0;
        startTimer(0);
        changeMode(mode_sailing);
    }

    //
    // called when we get GPS updates
    // 
    // info -- GPS information from the watch
    //
    function onPositionUpdate(info) {
        // create a session if we've started a timer and have GPS
        if (timerZero != null && $.session == null) {
            System.println("starting to record");
            $.session = Record.createSession({ :name => "sailing", :sport => Record.SPORT_GENERIC });
            $.session.start();
        }

        $.speed = info.speed;
        $.gpsAccuracy = info.accuracy;
        $.heading = info.heading;

        Ui.requestUpdate();
    }

    //
    // Handle down button presses.  Functionality varies depending on mode
    //
    function onDownKey() 
    {
        switch (mode) {
            case mode_prep:
                timerDuration = timerDuration - 60;
                if (timerDuration < 0)
                {
                    timerDuration = 0;
                }
                break;
            case mode_insequence:
                sync(false);
                break;
            case mode_sailing:
                break;
            case mode_finish:
                break;
            default:
                break;
        }
        return true;
    }

    //
    // Handle up button presses.  Functionality varies depending on mode
    //
    function onUpKey()
    {
        switch (mode) {
            case mode_prep:
                timerDuration = timerDuration + 60;
                break;
            case mode_insequence:
                sync(true);
                break;
            case mode_sailing:
                break;
            case mode_finish:
                break;
            default:
                break;
        }
        return true;
    }

    //
    // Insert mode-specific menu items when the menu button is pressed
    //
    function addViewMenuItems(menu)
    {
        System.println("adding view menu items for timer");
        switch (mode)
        {
            case mode_prep:
                menu.addItem(new Ui.MenuItem("Just Sail", "Start Session Now!", :justSail, {}));
                break;
            case mode_insequence:
                menu.addItem(new Ui.MenuItem("Reset", "Reset Timer", :resetTimer, {}));
                break;
            case mode_sailing:
                menu.addItem(new Ui.MenuItem("Reset", "Reset Timer", :resetTimer, {}));
                break;
            case mode_finish:
                menu.addItem(new Ui.MenuItem("Reset", "Reset Timer", :resetTimer, {}));
                menu.addItem(new Ui.MenuItem("Clear Finish", "Clear Finish Times", :clearFinish, {}));
                break;
            default:
                break;
        }
    }

    //
    // Handle mode-specific menu items
    //
    function viewMenuItemSelected(symbol, item)
    {
        var reset = false;
        switch (symbol)
        {
            case :justSail:
                justSail();
                break;
            case :resetTimer:
                reset = true;
                break;
            case :clearFinish:
                clearFinish();
                break;
            default:
                return false;
                break;
        }
        Ui.popView(Ui.SLIDE_DOWN);
        if (reset)
        {
            promptReset();
        }
        return true;
    }

    //
    // Start the timer, we're racing.  We don't also use this for stop
    // because we don't want an accidental press, the user needs to 
    // go into the menu for that.
    //
    function onEnterKey() {
        if (timerZero == null) 
        {
            startTimer(self.timerDuration);
        } 
        else if (mode == mode_sailing)
        {
            finishTimer();
        }
        return true;
    }

    // 
    // Finish button was pressed, record the time and update the list
    //
    function finishTimer()
    {
        if (finishTimes == null)
        {
            finishTimes = new[4];
            finishTimes[0] = Time.now();
        }
        else
        {
            var c = finishTimes.size();
            for (var i = 2; i < c; i++)
            {
                finishTimes[i - 1] = finishTimes[i];
            }
            finishTimes[c - 1] = Time.now();
        }
    }

    //
    // return the duration string in minutes and seconds given a time
    // in seconds
    // input: duration in seconds (int)
    // returns: text string to show the user
    //
    function durationText(duration) {
        var seconds = duration;
        var minutes = seconds / 60;
        var hours = minutes / 60;
        seconds = seconds % 60;

        if (hours > 0) {
            // hh:mm:ss, used during count-up timer in racing
            minutes = minutes % 60;
            return hours.format("%02u") + ":" + minutes.format("%02u") + ":" + seconds.format("%02u");
        } else {
            // mm:ss for sub-one-hour
            return minutes.format("%02u") + ":" + seconds.format("%02u");
        }
    }

    //
    // Load your resources here
    //
    function onLayout(dc) {
        switch (mode) {
            case mode_prep:
                System.println("mode: prep");
                setLayout(Rez.Layouts.TimerViewPrep(dc));
                break;
            case mode_insequence:
                System.println("mode: in sequence");
                setLayout(Rez.Layouts.TimerViewInSequence(dc));
                break;
            case mode_sailing:
                System.println("mode: sailing");
                setLayout(Rez.Layouts.TimerViewSailing(dc));
                break;
            case mode_finish:
                System.println("mode: finish");
                setLayout(Rez.Layouts.TimerViewFinish(dc));
                break;
            default:
                break;
        }
        modeView = mode;

        CommonView.onLayout(dc);
        System.println("TimerView.onLayout()");

        quarterWidth = dc.getWidth() / 4;

    }

    //
    // Update the view
    //
    function onUpdate(dc) {
        // change the layout if we don't have the correct one
        if (modeView != mode)
        {
            onLayout(dc);
        }

        var bgcolor = Graphics.COLOR_BLACK;
        var fgcolor = Graphics.COLOR_WHITE;

        // figure out the current system time
    	var now = Time.now();
    	var timestruct = Gregorian.info(now, Time.FORMAT_SHORT);
        var timerDone = false;
        var timerText = durationText(timerDuration);

        if (timerZero != null) {
            // special processing for after a timer has started

            // figure out the current timer time
            var duration = now.subtract(timerZero);
            duration = duration.value();
            timerText = durationText(duration);

            // is the countdown over?
            timerDone = now.greaterThan(timerZero);

            if (timerDone && mode == mode_insequence)
            {
                changeMode(mode_sailing);
            }

            // if we are at a minute boundary than buzz the watch
            if (!timerDone && duration % 60 == 0)
            {
                var minute = duration / 60;
                if (lastVibrationDuration != duration)
                {
                    var vibrateData;

                    if (minute == 0) {
                        // go!
                        vibrateData = [
                            new Attention.VibeProfile(50, 100),
                            new Attention.VibeProfile(0, 100),
                            new Attention.VibeProfile(100, 100),
                            new Attention.VibeProfile(0, 100),
                            new Attention.VibeProfile(100, 100)
                        ];

                        // we add a lap for when the race actually started
                        if ($.session == null) {
                            $.session = Record.createSession({ :name => "sailing", :sport => Record.SPORT_GENERIC });
                            $.session.start();
                        }
                        $.session.addLap();
                    } else if (minute == ((timerDuration / 60) - 1) || minute == 1) {
                        // flag change
                        vibrateData = [
                            new Attention.VibeProfile(100, 100),
                            new Attention.VibeProfile(0, 100),
                            new Attention.VibeProfile(100, 100)
                        ];
                    } else {
                        // normal minute
                        vibrateData = [
                            new Attention.VibeProfile(100, 100)
                        ];
                    }

                    Attention.vibrate(vibrateData);
                    lastVibrationDuration = duration;
                }
            } 
            else if (!timerDone && duration < 60 && duration % 10 == 0 && duration != lastVibrationDuration)
            {
                // every 10 seconds in last minute
                Attention.vibrate([ new Attention.VibeProfile(100, 50) ]);
                lastVibrationDuration = duration;
            }
            else if (!timerDone && duration < 10 && duration != lastVibrationDuration)
            {
                // every 1 second in last 10 seconds
                Attention.vibrate([ new Attention.VibeProfile(100, 50) ]);
                lastVibrationDuration = duration;
            }
        }

        // update local fields
        $.fields[TIMER_FIELD].setValue(timerText);

        // update fields in the view
        for (var i = 0; i < 3; i++)
        {
            if (self.timerFields[i] != null)
            {
                setTextOnField("FieldValue" + i, self.timerFields[i].value());
                setTextOnField("FieldLabel" + i, self.timerFields[i].label());
                setTextOnField("FieldUnits" + i, self.timerFields[i].units());
            }
        }

        // set finish text in view
        if (finishTimes != null)
        {
            var lastFinish = null;

            // fix the mode
            if (mode != mode_finish) 
            {
                changeMode(mode_finish);
            }

            // update the time fields
            var finish_index = 0;
            for (var i = 0; i < finishTimes.size(); i++)
            {
                // empty values if there is no finish in this slot
                //System.println("i = " + i);
                //System.println("finishTimes[i] = " + finishTimes[i]);
                //System.println("timerZero = " + timerZero);
                if (finishTimes[i] == null) { 
                    continue;
                }

                var duration = finishTimes[i].subtract(timerZero);
                var offset;
                if (lastFinish == null) 
                {
                    offset = "*1st*";
                }
                else
                {
                    offset = lastFinish.subtract(finishTimes[i]);
                    offset = "+" + offset.value() + " sec";
                }
                duration = duration.value();
                var finishTimerText = durationText(duration);

                var timestruct = Gregorian.info(finishTimes[i], Time.FORMAT_SHORT);
                var clockTime = timestruct.hour.format("%02u") + ":" + timestruct.min.format("%02u") + ":" + timestruct.sec.format("%02u");

                setTextOnField("FinishClock" + finish_index, clockTime);
                setTextOnField("FinishTimer" + finish_index, finishTimerText);
                setTextOnField("FinishOffset" + finish_index, offset);

                finish_index = finish_index + 1;
                lastFinish = finishTimes[0];
            }

            for (var i = finish_index; i < finishTimes.size(); i++) 
            {
                setTextOnField("FinishClock" + i, "");
                setTextOnField("FinishTimer" + i, "");
                setTextOnField("FinishOffset" + i, "");
            }
        }

        // this will show our layout
        CommonView.onUpdate(dc);

        // draw a G in the upper left showing GPS status
        // BUGBUG - move into layout
        dc.setColor(GpsAccuracyColor($.gpsAccuracy), Graphics.COLOR_TRANSPARENT);
        dc.drawText(32, 25, Graphics.FONT_XTINY, "G", Graphics.TEXT_JUSTIFY_LEFT);

        if ($.session != null && $.session.isRecording())
        {
            dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(screenWidth - 40, 39, 4);
        }
    }

    //
    // Called when this View is removed from the screen. Save the
    // state of this View here. This includes freeing resources from
    // memory.
    //
    function onHide() {
        CommonView.onHide();

        return true;
    }
}
