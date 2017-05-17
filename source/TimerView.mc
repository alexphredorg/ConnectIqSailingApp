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

class TimerView extends CommonView {
    // timerZero is when the timer will display 00:00.  If it is null
    // then no timer is running (we're in "Prep").  If (now - timerZero)
    // is positive then the timer is counting up and we're racing.  If 
    // it is negative then the timer is counting down and we're 
    // in start sequence.
    var timerZero;
    // how long should the timer be set to when the timer is reset?
    var timerDuration = 300;
    // do we have menu buttons on the screen?
    var inputMode = 0;
    // one quarter of the screen in pixels 
    var quarterWidth;
    // the font that we use when drawing buttons

    // remember when we last vibrated the watch, we do this to make sure that we don't vibrate
    // multiple times in the same second
    var lastVibrationDuration = 0;

    //
    // initialize the view
    //
    function initialize() {
        showSeconds = true;
        CommonView.initialize("timer");
    }

    //
    // Esc key is used to exit the app from the timer screen
    //
    function onEscKey()
    {
        self.quitDialog();
    }

    //
    // called when the user clicks on the screen.  We use this for the 
    // on screen buttons.
    //
    // inputs:
    //   evt -- tap event which tells us where the user tapped the screen
    //
    function screenTap(evt) {
        System.println("screen tap");
        if (evt.getType() == Ui.CLICK_TYPE_TAP && inputMode > 0) {
            inputMode = 0;
            var coords = evt.getCoordinates();
            System.println("tap at " + coords[0] + "," + coords[1]);
            if (coords[1] < 40)
            {
                // maps to one of two buttons at the top of the screen
                // timer running: reset, sync
                // timer not running: -1 minute, +1 minute
                if (coords[0] < quarterWidth * 2)
                {
                    if (timerZero != null) {
                        reset();
                    } else {
                        if (timerDuration > 0) {
                            timerDuration = timerDuration - 60;
                        }
                        onMenu();
                    }
                } else {
                    if (timerZero != null) {
                        sync();
                    } else {
                        timerDuration = timerDuration + 60;
                        onMenu();
                    }
                }
            } else if (timerZero == null && coords[1] > screenHeight - 35) {
                // this is where the "just sail!" button is located
                timerDuration = 0;
                startTimer();
            }
            Ui.requestUpdate();
        } 

        return true;
    }

    //
    // Start the timer (occurs on enter button press).  This also 
    // starts recording a session (as soon as we have GPS).
    //
    function startTimer() {
        System.println("starting new timer");
        // starting a fresh timer
        timerZero = Time.now();
        timerZero = timerZero.add(new Time.Duration(timerDuration));
        inputMode = 0;
    }

    //
    // called when we need to sync to the nearest minute
    // this modifies timerZero
    //
    function sync()
    {
        var now = Time.now();
        var duration = now.subtract(timerZero);
        var seconds = duration.value();
        var minutes = seconds / 60;
        seconds = seconds % 60;
        timerZero = now;
        if (seconds > 30) {
            timerZero = timerZero.add(new Time.Duration((minutes + 1) * 60));
        } else {
            timerZero = timerZero.add(new Time.Duration((minutes) * 60));
        }
    }

    //
    // reset the timer.  This also stops recording a session.
    //
    function reset() { 
        if ($.session != null) {
            $.session.stop();
            $.session.save();
            $.session = null;
            $.speed = -1;
        }
        timerZero = null;
        inputMode = 0;
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
    // put up the touch control menu
    //
    function onMenu() {
        inputMode = 100;
        System.println("in input mode");
        return true;
    }

    //
    // Start the timer, we're racing.  We don't also use this for stop
    // because we don't want an accidental press, the user needs to 
    // go into the menu for that.
    //
    function onEnterKey() {
        if (timerZero == null) {
            startTimer();
        } 
        return true;
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
        CommonView.onLayout(dc);
        System.println("TimerView.onLayout()");

        quarterWidth = dc.getWidth() / 4;
    }

    //
    // Update the view
    //
    function onUpdate(dc) {
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

        dc.setColor(bgcolor, bgcolor);
        dc.clear();
        dc.setColor(fgcolor, Graphics.COLOR_TRANSPARENT);

        var fields;
        var fieldLabels;
        var fieldUnits;
        var fieldFonts = [ Graphics.FONT_NUMBER_THAI_HOT, Graphics.FONT_NUMBER_HOT ];
        var headingText = ($.heading * 57.2957795);
        if (headingText < 0) { headingText += 360; }

        headingText = headingText.format("%02.0f");
        if (!timerDone) {
            // view for when timer is counting down
            fields = [ timerText, headingText ];
            fieldLabels = [ "timer", "COG" ];
            fieldUnits = [ "", "deg" ];
            showSpeed = true;
        } else {
            // view for racing
            var knots = $.speed * 1.94384449;
            var speedText = knots.format("%02.1f");
            fields = [ speedText, headingText ];
            fieldLabels = [ "SOG", "COG" ];
            fieldUnits = [ "kts", "deg" ];
            showSpeed = false;

            // this puts the timer in the bottom left (where speed normally is)
            // when the timer has completed.  It counts up at that point.
            dc.drawText(0, dc.getHeight() - dc.getFontHeight(clockSpeedFont), clockSpeedFont, timerText, Graphics.TEXT_JUSTIFY_LEFT);
        }

        var y = 35;
        dc.drawLine(0, y, screenWidth, y);
        for (var i = 0; i < fields.size(); i++) {
            dc.drawText(0, y, Graphics.FONT_XTINY, fieldLabels[i], Graphics.TEXT_JUSTIFY_LEFT);
            y += dc.getFontHeight(Graphics.FONT_XTINY) / 3;
            dc.drawText(quarterWidth * 2, y, fieldFonts[i], fields[i], Graphics.TEXT_JUSTIFY_CENTER);
            dc.drawText(screenWidth - 1, y + dc.getFontHeight(fieldFonts[i]) - dc.getFontHeight(Graphics.FONT_XTINY) + 3, Graphics.FONT_XTINY, fieldUnits[i], Graphics.TEXT_JUSTIFY_RIGHT);
            y += dc.getFontHeight(fieldFonts[i]) + 5;
            dc.drawLine(0, y, screenWidth, y);
        }

        // buttons get the top 35 pixels
        if (inputMode > 0)
        {
            if (timerZero == null) {
                showClock = false;
                showSpeed = false;
                dc.fillRoundedRectangle(2, 2, (quarterWidth * 2) - 2, 33, 2);
                dc.fillRoundedRectangle((quarterWidth * 2) + 2, 2, (quarterWidth * 2) - 2, 33, 2);
                dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
                dc.fillRoundedRectangle(2, screenHeight - 35, screenWidth - 2, screenHeight - 2, 2);
                dc.setColor(bgcolor, Graphics.COLOR_TRANSPARENT);
                dc.drawText(quarterWidth * 1, 7, Graphics.FONT_SMALL, "-1:00", Graphics.TEXT_JUSTIFY_CENTER);
                dc.drawText(quarterWidth * 3, 7, Graphics.FONT_SMALL, "+1:00", Graphics.TEXT_JUSTIFY_CENTER);
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
                dc.drawText(quarterWidth * 2, screenHeight - 28, Graphics.FONT_SMALL, "Just Sail", Graphics.TEXT_JUSTIFY_CENTER);
            } else {
                showClock = true;
                dc.fillRoundedRectangle(2, 2, (quarterWidth * 2) - 2, 33, 2);
                dc.fillRoundedRectangle((quarterWidth * 2) + 2, 2, (quarterWidth * 2) - 2, 33, 2);
                dc.setColor(bgcolor, Graphics.COLOR_TRANSPARENT);
                dc.drawText(quarterWidth * 1, 7, Graphics.FONT_SMALL, "reset", Graphics.TEXT_JUSTIFY_CENTER);
                dc.drawText(quarterWidth * 3, 7, Graphics.FONT_SMALL, "sync", Graphics.TEXT_JUSTIFY_CENTER);
            }
        } else {
            showClock = true;
            var mode = "Sailing";
            if (timerZero == null) {
                mode = "Prep";
            } else if (!timerDone) {
                mode = "In Sequence";
            }
            dc.drawText(quarterWidth * 2, 0, Graphics.FONT_LARGE, mode, Graphics.TEXT_JUSTIFY_CENTER);

            // draw a G in the upper left showing GPS status
            dc.setColor(GpsAccuracyColor($.gpsAccuracy), Graphics.COLOR_TRANSPARENT);
            dc.drawText(0, 0, Graphics.FONT_XTINY, "G", Graphics.TEXT_JUSTIFY_LEFT);

            if ($.session != null && $.session.isRecording())
            {
                dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(screenWidth - 7, 8, 6);
            }
        }

        CommonView.onUpdate(dc);
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
