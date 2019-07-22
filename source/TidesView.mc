using Toybox.WatchUi as Ui;
using Toybox.Time as Time;
using Toybox.Time.Gregorian as Gregorian;
using Toybox.Lang as Lang;
using Toybox.System as System;
using Toybox.Timer as Timer;
using Toybox.Position as Position;
using Toybox.Attention as Attention;
using Toybox.Communications as Comm;
using Toybox.Application as App;

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
    const MAX_SCREEN_WIDTH = 180;
    const MIN_SCREEN_HEIGHT = 205;

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
    var fComputingData = false;

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

    var stationName = null;
    var refreshCount = 1;

    // menu item IDs
    var quitMenuItem = -1;
    var findStationsMenuItem = -1;

    // GPS data
    var position = null;

    // are we getting data from the internet?
    var fOnline = false;

    // shift for wide screens
    var screenBiasX = 0;
    var screenBiasY = 0;

    //
    // initialize the view
    //
    function initialize() {
        System.println("TidesView.initialize");
        highSpeedRefresh = false;
        CommonView.initialize("tides");

        // this class makes assumptions that don't work on wider screens
        if (screenWidth > MAX_SCREEN_WIDTH) 
        {
            screenBiasX = (screenWidth - MAX_SCREEN_WIDTH) / 2;
            screenWidth = MAX_SCREEN_WIDTH;
            screenBiasY = (screenHeight - MIN_SCREEN_HEIGHT) / 2;
        }

        timer = new Timer.Timer();

        // see if we have a saved tide station.  If so we'll plot that one
        tideStation = new TideStationFromObjectStore();
        if (tideStation.validStation())
        {
            stationName = tideStation.name();
        }

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
    // Get the tide station list from the object store
    //
    function getTideStationList() 
    {
        var app = App.getApp();
        var stationList = app.getProperty("TideStationList");
        if (stationList == null || !(stationList instanceof Toybox.Lang.Array))
        {
            stationList = [];
        }
        return stationList; 
    }

    //
    // put the list of tide stations into the menu
    //
    function addViewMenuItems(menu)
    {
        System.println("tides menu");
        var stationList = getTideStationList();
        if (stationList == null) 
        {
            stationList = [];
        }

        for (var i = 0; i < stationList.size(); i++) {
            menu.addItem(new Ui.MenuItem(stationList[i]["name"], "Select Tide Station", :tideStation, {}));
        } 

        menu.addItem(new Ui.MenuItem("Find", "Find Nearby Stations", :find, {}));
    }

    // 
    // handle folder menu items
    //
    function viewMenuItemSelected(symbol, item)
    {
        if (symbol == :tideStation)
        {
            var stationIndex = -1;
            var stationList = getTideStationList();
            for (var i = 0; i < stationList.size(); i++)
            {
                System.println(item.getLabel() + " compare " + stationList[i]["name"]);
                if (stationList[i]["name"] == item.getLabel())
                {
                    stationIndex = i;
                }
            }
            if (stationIndex >= 0)
            {
                System.println("selecting station id: " + stationList[stationIndex]["id"]);
                requestStationInfo(stationList[stationIndex]["id"]);
                Ui.popView(Ui.SLIDE_DOWN);
                return true;
            }
        }
        else if (symbol == :find)
        {
            // get a new list of stations
            requestStationList();
            Ui.popView(Ui.SLIDE_DOWN);
        }
        return false;
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

    // tide station information.  This is unloaded after we generate tide data.
    var tideStation = null;

    //
    // start the process of rendering new tide data.  This is computationally
    // expensive (for a watch) and so we do it in an async called helper 
    // method to avoid hitting the watch's watchdog timer
    //
    function requestTideData() {
        tideStation = new TideStationFromObjectStore();
        if (!tideStation.validStation()) 
        {
            stationName = null;
        } 
        else 
        {
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
            var height = computeTideHeight(tideStation, year, currHours);

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
        tideStation = null;

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
    // called when the position is updated by GPS. 
    // 
    function onPositionUpdate(info) 
    {
        if (info.position == null)
        {
            self.position = null;
        }
        else
        {
            self.position = info.position.toDegrees();
        }
    }

    //
    // request data for a tide station from the internet
    //
    function requestStationInfo(id)
    {
        fOnline = true;
        var app = App.getApp();
        var tideStationId = app.getProperty("TideStationId");
        var url = "http://www.phred.org:18266/TideStation/" + id;
        System.println("tide: url = " + url);
        httpGetJson(url, :onReceiveStationInfo);
    }

    //
    // Callback for requestStationInfo
    //
    // responseCode -- HTTP response code when doing the JSON request
    // data -- the raw data that is received
    //
    function onReceiveStationInfo(responseCode, data) 
    {
        System.println("tides: onReceiveStationInfo(): " + responseCode);
        var errorInfo = "";

        if (responseCode == 200) 
        {
            // validate the data format.  
            if (data["station"] != null && data["station"] instanceof Toybox.Lang.Dictionary)
            {
                var station = data["station"];
                if (station["name"] != null && station["name"] instanceof Toybox.Lang.String &&
                    station["datum"] != null && station["datum"] instanceof Toybox.Lang.Float &&
                    station["amp"] != null && station["amp"] instanceof Toybox.Lang.Array &&
                    station["epoch"] != null && station["epoch"] instanceof Toybox.Lang.Array &&
                    station["speed"] != null && station["speed"] instanceof Toybox.Lang.Array &&
                    station["equilibrium"] != null && station["equilibrium"] instanceof Toybox.Lang.Dictionary &&
                    station["node_factor"] != null && station["node_factor"] instanceof Toybox.Lang.Dictionary)
                {
                    var app = App.getApp();
                    app.setProperty("TideStationInfo", data["station"]);
                    stationName = data["station"]["name"];
                    self.requestTideData();
                    self.fOnline = false;
                    return;
                }
                errorInfo = "Invalid station list data";
            }
            else if (data["error"] != null && data["error"] instanceof Toybox.Lang.String)
            {
                errorInfo = data["error"];
            }
        }
        System.println("Error: " + errorInfo);
        self.fOnline = false;
    }

    //
    // request data for the list of nearby tide stations from the internet
    //
    // returns: false if no known position, true otherwise
    //
    function requestStationList()
    {
        if (position == null) 
        {
            return false;
        }
        self.fOnline = true;
        var url = "http://www.phred.org:18266/TideStations/" + position[0] + "," + position[1];
        httpGetJson(url, :onReceiveStationList);
        return true;
    }

    //
    // Callback for requestStationList
    //
    // responseCode -- HTTP response code when doing the JSON request
    // data -- the raw data that is received
    //
    function onReceiveStationList(responseCode, data) 
    {
        System.println("tides: onReceiveStationList(): " + responseCode);
        var errorInfo = "";

        if (responseCode == 200) 
        {
            System.println(data);
            // validate the data format.  
            if (data["stations"] != null && data["stations"] instanceof Toybox.Lang.Array)
            {
                System.println("stations list found");
                var stationCount = data["stations"].size();
                for (var i = 0; i < stationCount; i++)
                {
                    var station = data["stations"][i];
                    System.println("station: " + station);
                    if (station instanceof Toybox.Lang.Dictionary)
                    {
                        if (station["name"] != null && station["name"] instanceof Toybox.Lang.String &&
                            station["id"] != null && station["id"] instanceof Toybox.Lang.Number)
                        {
                            var app = App.getApp();
                            app.setProperty("TideStationList", data["stations"]);
                            self.fOnline = false;
                            onMenu();
                            return;
                        }
                    }
                }
                errorInfo = "Invalid station list data";
            }
            else if (data["error"] != null && data["error"] instanceof Toybox.Lang.String)
            {
                errorInfo = data["error"];
            }
        }

        System.println("Error: " + errorInfo);
        self.fOnline = false;
    }


    //
    // Draw error or other text on the screen.  
    //
    function renderText(dc, font, textArray)
    {
        //
        // No tide station selected
        //
        var y = 0;
        y += dc.getFontHeight(font) + 4;
        for (var i = 0; i < textArray.size(); i++)
        {
            dc.drawText(screenWidth / 2 + screenBiasX, y, font, textArray[i], Graphics.TEXT_JUSTIFY_CENTER);    
            y += dc.getFontHeight(font);
        }
        return y;
    }

    // Load your resources here
    function onLayout(dc) {
        Ui.View.setLayout(Rez.Layouts.TidesView(dc));
        CommonView.onLayout(dc);
    }

    //
    // Render the view
    //
    function onUpdate(dc) {
        // CommonView draws the time and boat speed
        CommonView.onUpdate(dc);

        var bgcolor = Graphics.COLOR_BLACK;
        var connected = System.getDeviceSettings().phoneConnected;
        var fgcolor = Graphics.COLOR_WHITE;

        if (stationName instanceof Toybox.Lang.String)
        {
            stationName = CommonView.wordWrap(dc, TIDE_FONT, stationName);
        }

        if (fComputingData) 
        {
            //
            // We're still computing tides, show the user some sign of 
            // progress
            //
            var font = Graphics.FONT_MEDIUM;
            var y = self.renderText(dc, font, [ "Computing", "Tides" ]);
            var dots = "";
            for (var i = 0; i < batch; i++) { dots = dots + "."; }
            dc.drawText(screenWidth / 2 + screenBiasX, y, font, dots, Graphics.TEXT_JUSTIFY_CENTER);    
        } 
        else if (fOnline)
        {
            //
            // We're download station information
            //
            self.renderText(dc, Graphics.FONT_MEDIUM, [ "Downloading", "Tide Info" ]);
        } 
        else if (stationName == null && connected && position != null)
        {
            //
            // No tide station selected
            //
            self.renderText(dc, Graphics.FONT_MEDIUM, [ "Press Menu", "to Select a", "Tide Station" ]);
        }
        else if (stationName == null)
        {
            //
            // No tide station selected and no GPS or data
            //
            self.renderText(dc, Graphics.FONT_MEDIUM, [ "Connect phone", "and enable GPS", "to view Tides" ]);
        }
        else 
        {
            //
            // draw our tides screen
            //
            var fontHeight = dc.getFontHeight(TIDE_FONT);

            // top of the screen has the name of the tide station
            dc.setColor(fgcolor, Graphics.COLOR_TRANSPARENT);
            var stationNameIndex = (refreshCount / 2) % stationName.size();
            refreshCount++;
            dc.drawText(screenWidth / 2 + screenBiasX, screenBiasY, TIDE_FONT, stationName[stationNameIndex], Graphics.TEXT_JUSTIFY_CENTER);

            // below that is a tide graph that is TIDE_PIXELs tall.  The 
            // graph is scaled to fit our tides.

            var scaleFactor = TIDE_PIXELS / (maxTidalHeight - minTidalHeight);
            var graphTop = screenBiasY + fontHeight + 3;
            var graphBottom = graphTop + TIDE_PIXELS;
            // tide height at the time closest to now
            var nowHeight = 0;
            var nowX = 0;
            var tideGraphEnd = tideGraphStart + screenWidth;

            // draw out the points in the tide graph
            for (var x = tideGraphStart; x < tideGraphEnd; x++)
            {
                var dx = x - tideGraphStart + screenBiasX;
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
                    dc.drawLine(screenBiasX, y, screenBiasX + screenWidth, y);
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
            dc.drawText(screenBiasX, graphBottom, TIDE_FONT, tideGraphStartTime, Graphics.TEXT_JUSTIFY_LEFT);
            dc.drawText(screenBiasX + screenWidth - 1, graphBottom, TIDE_FONT, tideGraphEndTime, Graphics.TEXT_JUSTIFY_RIGHT);
            dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
            dc.drawText(nowX, graphBottom, TIDE_FONT, "now:" + nowHeight.format("%2.1f") + "ft", Graphics.TEXT_JUSTIFY_LEFT);

            // the rest of the screen is used for highlights
            var y = graphBottom + fontHeight + 4;
            for (var i = 0; i < cTidalHighlightData; i++) 
            {
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
                dc.drawText(screenBiasX + 5, y, TIDE_FONT, tidalHighlightData[i]["d"], Graphics.TEXT_JUSTIFY_LEFT);
                dc.setColor(fgcolor, Graphics.COLOR_TRANSPARENT);
                dc.drawText(nowX, y, TIDE_FONT, tidalHighlightData[i]["h"], Graphics.TEXT_JUSTIFY_LEFT);
                dc.drawText(nowX * 3, y, TIDE_FONT, tidalHighlightData[i]["t"], Graphics.TEXT_JUSTIFY_RIGHT);
                if (drawline && x >= tideGraphStart && x < tideGraphEnd) 
                {
                    x = x - tideGraphStart;
                    dc.setColor(color, Graphics.COLOR_TRANSPARENT);
                    dc.drawLine(screenBiasX + x, graphTop, screenBiasX + x, graphBottom);
                }
                y += fontHeight;
            }

            // if there are a lot of highlights then the big clock used by
            // the clock doesn't fit, make it smaller
            if (cTidalHighlightData > 4) 
            {
                clockSpeedFont = TIDE_FONT;
            } 
            else 
            {
                clockSpeedFont = Graphics.FONT_MEDIUM;
            }
        }
    }
}


//
// Data representing one tide station.  The data for this is loaded from the object store and was
// saved there by onReceiveStationInfo
//
class TideStationFromObjectStore {
    var stationInfo;
    function initialize() 
    {
        var app = App.getApp();
        stationInfo = app.getProperty("TideStationInfo");
        self.stationInfo = stationInfo;
    }
    function validStation() 
    {
        return (stationInfo != null);
    }
	function name() { return self.stationInfo["name"]; }
    function zoneOffset() { return self.stationInfo["zone_offset"]; }
	function datum() { return self.stationInfo["datum"]; }
	function amp() { return self.stationInfo["amp"]; }
	function epoch() { return self.stationInfo["epoch"]; }
	function speed() { return self.stationInfo["speed"]; }
	function equilarg(year) { return self.stationInfo["equilibrium"][year.toString()]; }
	function nodeFactor(year) { return self.stationInfo["node_factor"][year.toString()]; }
}
