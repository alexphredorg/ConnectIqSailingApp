using Toybox.WatchUi as Ui;
using Toybox.Time as Time;
using Toybox.Time.Gregorian as Gregorian;
using Toybox.Lang as Lang;
using Toybox.System as System;
using Toybox.Timer as Timer;
using Toybox.Position as Position;
using Toybox.Attention as Attention;
using Toybox.Communications as Comm;

class TidesView extends CommonView {
    // This set of constants is used to control how tides are rendered.
    const TIDE_FONT = Graphics.FONT_XTINY;
    const TIDE_POINTS_PER_BATCH = 40;
    const TIDE_POINT_PERIOD = 360;      
    const TIDE_BATCHES = 6;
    const TIDE_BACK_BATCHES = 2;
    const TIDE_BATCH_SECONDS = TIDE_POINTS_PER_BATCH * TIDE_POINT_PERIOD;   
    const TIDE_POINTS = TIDE_BATCHES * TIDE_POINTS_PER_BATCH;
    const TIDE_NOW_POINT = ((TIDE_BATCH_SECONDS / TIDE_POINT_PERIOD) * TIDE_BACK_BATCHES) + 1;
    const TIDE_HIGHLIGHT_ROWS = 9;
    const TIDE_GRAPH_START = TIDE_POINTS_PER_BATCH * 1;

    // vertical screen area for tide chart
    const TIDE_PIXELS = 50;

    // we use a background timer to keep long running math operations 
    // going.  This is a hack to work around the watchdog timer built into
    // the watch that will kill long running compute operations
    var timer = null;

    // tidalData is an array of floats which contains the tidal height at
    // each point.  Each point is (TIDE_POINT_PERIOD) seconds past the 
    // previous point
    var tidalData = new [TIDE_POINTS];

    // tidalTime is a parallel array to tidalData that contains the time
    // in minutes since midnight that the point is valid for
    var tidalTime = new [TIDE_POINTS];

    // this is set to true when we are computing tide data.  We don't
    // render during that time
    var fComputingData = true;

    // text data for high and low points in the tidal cycle. 
    // each entry is a dict with the following structure
    // { "t" => text to show,
    //   "c" => color for the line,
    //   "i" => index into tidalData that this refers to
    // };
    var tidalHighlightData = new [TIDE_HIGHLIGHT_ROWS];

    // count of valid entries in tidalHighlightData
    var cTidalHighlightData = 0;

    // min and max tidal heights
    var minTidalHeight = 9999;
    var maxTidalHeight = -9999;
    var lastPredictionTime = null;
    var lastPredictionHeight = null;
    var lastPredictionSlope = 0;

    // graph window
    var tideGraphStart;
    var tideNowPoint = TIDE_NOW_POINT;
    var momentStart;

    //
    // This is the list of supported tide stations.
    // TODO: Figure out a way to load this from a file on the device
    // instead of having it cooked into our binary.  These consume a lot
    // of program space
    //
    var stations = [
        new Tacoma(),
        new Seattle(),
        new PortTownsend(),
        new PortAngeles(),
        new FridayHarbor(),
        new NeahBay()
    ];

    // What is the active station
    var iStation = 1;

    //
    // initialize the view
    //
    function initialize() {
        CommonView.initialize("tides");

        timer = new Timer.Timer();

        // start generating tide data
        requestTideData();
    }

    //
    // moveWindow is called by the timer to adjust the view to the current
    // time
    //
    function moveWindow() {
        System.println("move window");
        if (!fComputingData) {
            tideGraphStart = tideGraphStart + 1;
            tideNowPoint = tideNowPoint + 1;

            var sixMinutes = new Time.Duration(6 * 60);
            momentStart = momentStart.add(sixMinutes);

            // reload the data if we are almost out of points
            if (tideGraphStart + screenWidth + 5 > TIDE_POINTS)
            {
                requestTideData();
            }

            Ui.requestUpdate();
        } else {
            requestTideData();
        }
    }

    //
    // when the menu button is pressed.  We create a custom menu that lists
    // all of the stations
    //
    function onMenu() {
        resetMenu();
        menu.setTitle("Select Tide Station");
        for (var i = 0; i < stations.size(); i++) {
            var stationName = stations[i].stationName();
            var openParen = stationName.find("(");
            if (openParen != null && openParen > 0) {
                stationName = stationName.substring(0, openParen);
            }
            addMenuItem(stationName);
        } 
        showMenu();
        return true;
    }

    //
    // called by TidesMenuInput when a new tide station is selected
    // inputs:
    //  stationIndex -- the index into stations[] for the new selected tide
    //                  station
    //
    function menuItemSelected(stationIndex) {
        iStation = stationIndex;
        requestTideData();
    }

    //
    // used to cycle through wind stations
    //
    function onSwipeUp() {
        iStation = (iStation + 1) % stations.size();
        requestTideData();
        return true;
    }

    //
    // used to cycle through wind stations
    //
    function onSwipeDown() {
        iStation--;
        if (iStation < 0) { iStation = stations.size() - 1; }
        requestTideData();
        return true;
    }

    //
    // global variables related to tide calculations
    //

    // the current year
    var year;
    // hours since the start of the year (used for calculations)
    var currHours;
    // minutes since the start of the day (used for display)
    var currMinutes;
    // how far to increment currHours based on TIDE_POINT_PERIOD
    var hourIncrement;
    // how far to increment currMinutes based on TIDE_POINT_PERIOD
    var minIncrement;
    // what batch are we currently generating?
    var batch;
    // how much of tidalData have we filled up?
    var iTidalData;

    //
    // start the process of rendering new tide data.  This is computationally
    // expensive (for a watch) and so we do it in an async called helper 
    // method to avoid hitting the watch's watchdog timer
    //
    function requestTideData() {
        fComputingData = true;

        var startOfYear = Gregorian.moment({:day=>1, :month=>1, :hour=>0, :minute=>0, :second=>0});
        var now = Gregorian.now();
        var start = now.add(new Time.Duration(-TIDE_BATCH_SECONDS * TIDE_BACK_BATCHES));
        var startInfo = Gregorian.info(start, Time.FORMAT_SHORT);
        var nowInfo = Gregorian.info(now, Time.FORMAT_SHORT);
        year = nowInfo.year;

        currHours = (start.value() - startOfYear.value()) / 3600;
        currHours = currHours.toDouble();
        currMinutes = nowInfo.hour * 60 + nowInfo.min;
        currMinutes -= (TIDE_BATCH_SECONDS * TIDE_BACK_BATCHES / 60);
        minIncrement = TIDE_POINT_PERIOD / 60;
        hourIncrement = TIDE_POINT_PERIOD.toFloat() / 3600;
        iTidalData = 0;
        batch = 0;
        timer.stop();
        timer.start(method(:timerStep), 50, true);
    }

    // 
    // This is the callback for the timer used to compute tides. 
    //
    function timerStep() {
        if (batch == TIDE_BATCHES) {
            // we've generated all of the tide points, process them
            timer.stop();
            processAllTideData();
        } else {
            // generate the next set of tide points
            Ui.requestUpdate();
            generateNextTideData();
        }
    }

    //
    // This generates tide results for one batch of points
    //
    function generateNextTideData() {
        System.println("generateNextTideData: batch=" + batch);
        for (var i = 0; i < TIDE_POINTS_PER_BATCH; i++) {
            // increment our times
            currHours += hourIncrement;
            currMinutes += minIncrement;

            // compute the height for this time
            var height = computeTideHeight(stations[iStation], year, currHours);

            // save the results
            tidalData[iTidalData] = height.toFloat();
            tidalTime[iTidalData] = currMinutes;
            iTidalData++;
        }

        batch++;
    }

    //
    // This is called after all steps to generateNextTideData() are 
    // complete.  It is used to find the min/max tides
    //
    // We generate min/max tide times in a computationally simple way, but
    // not very accurately.  It is +/- TIDE_POINT_PERIOD
    //
    function processAllTideData() {
        minTidalHeight = -0.3;
        maxTidalHeight = -9999;
        lastPredictionTime = null;
        lastPredictionHeight = null;
        cTidalHighlightData = 0;
        tideGraphStart = TIDE_GRAPH_START;
        tideGraphStart = tideGraphStart.toNumber();
        tideNowPoint = TIDE_NOW_POINT;

        //
        // go through all tide points.  We're looking for the minimum tide
        // height, maximum tide height (used in rendering), and changes in
        // slope to detect high/low tide points.
        // 
        // high/low events are written to tidalHighlightData which is used
        // during rendering
        //
        for (var i = 0; i < tidalData.size(); i++) {
            var height = tidalData[i];
            var hour = (tidalTime[i] / 60) % 24;
            var min = tidalTime[i] % 60;
            var time = hour.format("%02u") + ":" + min.format("%02u");
            var highlight = null;

            tidalTime[i] = height;

            if (height < minTidalHeight) { minTidalHeight = height; }
            if (height > maxTidalHeight) { maxTidalHeight = height; }

            // special times on the graph.  These are off by one since we use the 
            // last... variables for the highlight info
            var highlightColor = null;

            if (i == TIDE_GRAPH_START) {
                momentStart = Gregorian.moment({ :hour => hour, :minute => min });
            }

            // detect low/high by looking for a slope change
            if (i > 0) {
                var slope = height - lastPredictionHeight;
                if (i > 1) {
                    if (lastPredictionSlope < 0 && slope >= 0) { 
                        highlightColor = Graphics.COLOR_DK_RED;
                        highlight = "low"; 
                    }
                    if (lastPredictionSlope >= 0 && slope < 0) { 
                        highlightColor = Graphics.COLOR_DK_GREEN;
                        highlight = "high"; 
                    }
                }
                lastPredictionSlope = slope;
            }

            // save everything necessary for a highlight point
            if (highlight != null) {
                tidalHighlightData[cTidalHighlightData] = {
                    "h" => lastPredictionHeight.format("%2.1f") + "ft",
                    "t" => lastPredictionTime,
                    "d" => highlight,
                    "c" => highlightColor,
                    "i" => i - 1
                };

                // we just overflow the last cell if we run out of space
                if (cTidalHighlightData < tidalHighlightData.size()) {
                    cTidalHighlightData++;
                }
            }
    
            lastPredictionTime = time;
            lastPredictionHeight = height;
        }

        // this timer will update our view until we run out of data
        timer.stop();
        timer.start(method(:moveWindow), 1000 * TIDE_POINT_PERIOD, true);

        fComputingData = false;

        Ui.requestUpdate();
    }

    // 
    // compute tide height for a station at a given time
    //
    // input: 
    //  stationInfo -- one of the tide station information classes
    //  year -- the year to produce tides for
    //  currHours -- the number of hours since 1/1/<year> 00:00:00
    // output:
    //  tide height in feet
    //
    function computeTideHeight(stationInfo, year, currHours) {
        var tideHeight;

        // load parameters from the station
        var nodeFactor = stationInfo.nodeFactor(year);
        var amp = stationInfo.amp();
        var equilarg = stationInfo.equilarg(year);
        var epoch = stationInfo.epoch();
        var speed = stationInfo.speed();

        // formula comes from http://www.flaterco.com/xtide/faq.html#260
        tideHeight = stationInfo.datum(); 
        for (var i = 0; i < amp.size(); i++) {
            tideHeight = tideHeight + 
                (amp[i] * nodeFactor[i] * Math.cos(Math.toRadians(
                    ((speed[i] * currHours) + equilarg[i] - epoch[i]))));
        }

        return tideHeight;  
    }

    //
    // Render the view
    //
    function onUpdate(dc) {
        var bgcolor = Graphics.COLOR_BLACK;
        var fgcolor = Graphics.COLOR_WHITE;

        dc.setColor(bgcolor, bgcolor);
        dc.clear();
        dc.setColor(fgcolor, Graphics.COLOR_TRANSPARENT);

        if (fComputingData) {
            //
            // We're still computing tides, show the user some sign of 
            // progress
            //
            var y = 0;
            var font = Graphics.FONT_LARGE;
            y += dc.getFontHeight(font) + 4;
            dc.drawText(screenWidth / 2, y, font, "Computing", Graphics.TEXT_JUSTIFY_CENTER);    
            y += dc.getFontHeight(font) + 4;
            dc.drawText(screenWidth / 2, y, font, "Tides", Graphics.TEXT_JUSTIFY_CENTER);    
            y += dc.getFontHeight(font) + 4;
            var dots = "";
            for (var i = 0; i < batch; i++) { dots = dots + "."; }
            dc.drawText(screenWidth / 2, y, font, dots, Graphics.TEXT_JUSTIFY_CENTER);    
        } else {
            //
            // draw our tides screen
            //
            var fontHeight = dc.getFontHeight(TIDE_FONT);

            // top of the screen has the name of the tide station
            dc.setColor(fgcolor, Graphics.COLOR_TRANSPARENT);
            dc.drawText(screenWidth / 2, 0, TIDE_FONT, stations[iStation].stationName(), Graphics.TEXT_JUSTIFY_CENTER);

            // below that is a tide graph that is TIDE_PIXELs tall.  The 
            // graph is scaled to fit our tides.

            var scaleFactor = TIDE_PIXELS / (maxTidalHeight - minTidalHeight);
            var graphTop = fontHeight + 3;
            var graphBottom = graphTop + TIDE_PIXELS;
            // tide height at the time closest to now
            var nowHeight = 0;
            var nowX = 0;
            var tideGraphEnd = tideGraphStart + screenWidth;

            // draw out the points in the tide graph
            for (var x = tideGraphStart; x < tideGraphEnd; x++)
            {
                var dx = x - tideGraphStart;
                if (x == tideNowPoint) {
                    // draw a yellow line at the current time
                    dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
                    dc.drawLine(dx, graphTop - 1, dx, graphBottom + 1);
                    nowHeight = tidalData[x];
                    nowX = dx;
                } else {
                    // this is a normal column, white on top, black dot, blue
                    // at the bottom
                    var y = graphBottom - ((tidalData[x] - minTidalHeight) * scaleFactor);
                    dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
                    dc.drawLine(dx, graphTop - 1, dx, y);
                    dc.setColor(Graphics.COLOR_BLUE, Graphics.COLOR_TRANSPARENT);
                    dc.drawLine(dx, y + 1, dx, graphBottom + 1);
                }
            }

            // draw horizontal reference lines.  I tried having more lines
            // (and it's easy to turn back on), but prefered the cleaner
            // graph with only a 0 line
            for (var r = 0; r <= 1; r += 5) {
                if (r > minTidalHeight && r < maxTidalHeight) {
                    var y = graphBottom - ((r - minTidalHeight) * scaleFactor);
                    if (r == 0) { 
                        dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
                    } else {
                        dc.setColor(Graphics.COLOR_DK_BLUE, Graphics.COLOR_TRANSPARENT);
                    }
                    dc.drawLine(0, y, screenWidth, y);
                }
            }

            //
            // just below the graph we have graph start and end times,
            // along with information on the current tide height
            var info = Gregorian.utcInfo(momentStart, Time.FORMAT_SHORT);
            var tideGraphStartTime = info.hour.format("%02u") + ":" + info.min.format("%02u");
            var momentEnd = momentStart.add(new Time.Duration(6 * 60 * screenWidth));
            info = Gregorian.utcInfo(momentEnd, Time.FORMAT_SHORT);
            var tideGraphEndTime = info.hour.format("%02u") + ":" + info.min.format("%02u");
            dc.setColor(fgcolor, Graphics.COLOR_TRANSPARENT);
            dc.drawText(0, graphBottom, TIDE_FONT, tideGraphStartTime, Graphics.TEXT_JUSTIFY_LEFT);
            dc.drawText(screenWidth - 1, graphBottom, TIDE_FONT, tideGraphEndTime, Graphics.TEXT_JUSTIFY_RIGHT);
            dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
            dc.drawText(nowX, graphBottom, TIDE_FONT, "now:" + nowHeight.format("%2.1f") + "ft", Graphics.TEXT_JUSTIFY_LEFT);

            // the rest of the screen is used for highlights
            var y = graphBottom + fontHeight + 4;
            for (var i = 0; i < cTidalHighlightData; i++) {
                var color = tidalHighlightData[i]["c"];
                var x = tidalHighlightData[i]["i"];
                var drawline = true;
                if (color == null) { color = fgcolor; drawline = false; }
                dc.setColor(fgcolor, Graphics.COLOR_TRANSPARENT);
                // h = height
                // t = time
                // d = description
                // d  h  t
                dc.setColor(color, Graphics.COLOR_TRANSPARENT);
                dc.drawText(5, y, TIDE_FONT, tidalHighlightData[i]["d"], Graphics.TEXT_JUSTIFY_LEFT);
                dc.setColor(fgcolor, Graphics.COLOR_TRANSPARENT);
                dc.drawText(nowX, y, TIDE_FONT, tidalHighlightData[i]["h"], Graphics.TEXT_JUSTIFY_LEFT);
                dc.drawText(nowX * 3, y, TIDE_FONT, tidalHighlightData[i]["t"], Graphics.TEXT_JUSTIFY_RIGHT);
                if (drawline && x >= tideGraphStart && x < tideGraphEnd) {
                    x = x - tideGraphStart;
                    dc.setColor(color, Graphics.COLOR_TRANSPARENT);
                    dc.drawLine(x, graphTop, x, graphBottom);
                }
                y += fontHeight;
            }

            // if there are a lot of highlights then the big clock used by
            // the clock doesn't fit, make it smaller
            if (cTidalHighlightData > 4) {
                clockSpeedFont = TIDE_FONT;
            } else {
                clockSpeedFont = Graphics.FONT_MEDIUM;
            }
        }
        // CommonView draws the time and boat speed
        CommonView.onUpdate(dc);
    }
}