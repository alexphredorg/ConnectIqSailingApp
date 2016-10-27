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
    // this is all hardcoded to the vivoactive HR screen
    const TIDE_FONT = Graphics.FONT_XTINY;
    const TIDE_POINT_PERIOD = 360;      // 6 minutes (defined by NOAA)
    const TIDE_BATCHES = 4;
    const TIDE_BATCH_SECONDS = 21600;   // in seconds, 6 hours
    const TIDE_BACK_BATCHES = 1.5;
    const TIDE_POINTS_PER_BATCH = (TIDE_BATCH_SECONDS / TIDE_POINT_PERIOD);
    const TIDE_POINTS = TIDE_BATCHES * TIDE_POINTS_PER_BATCH;
    const TIDE_NOW_POINT = ((TIDE_BATCH_SECONDS / TIDE_POINT_PERIOD) * TIDE_BACK_BATCHES) + 1;
    const TIDE_HIGHLIGHT_ROWS = 9;
    // screen area for tide chart
    const TIDE_PIXELS = 50;

    // the part of the data to show
    const TIDE_GRAPH_START = 50;

    var timer = null;

    // this holds 15 hours of tidal data (10 points per hour)
    // tidalData contains the heights measured as floats
    var tidalData = new [TIDE_POINTS];
    // tidalTime contains the times, measured in minutes since the start
    // of the day.  We can't afford to store strings or moments here or we
    // fill the object store
    var tidalTime = new [TIDE_POINTS];
    var fGotData = false;
    var errorText = null;

    // text data for key points in the tide cycle
    // each entry is a dict with the following structure
    // { "t" => text to show,
    //   "c" => color for the line,
    //   "i" => index into tidalData that this refers to
    // };
    var tidalHighlightData = new [TIDE_HIGHLIGHT_ROWS];

    // state information for making requests to get tidal data
    var startTimes = new [TIDE_BATCHES];
    var endTimes = new [TIDE_BATCHES];
    var cTidalHighlightData = 0;

    // min and max tidal heights
    var minTidalHeight = 9999;
    var maxTidalHeight = -9999;
    var lastPredictionTime = null;
    var lastPredictionHeight = null;
    var lastPredictionSlope = 0;

    // graph window
    var tideGraphStart = TIDE_GRAPH_START;
    var tideNowPoint = TIDE_NOW_POINT;
    var momentStart;

    var requestsOutstanding = 0;

    var stations = [
        { "id" => 9449856, "name" => "San Juan Island" },
        { "id" => 9444900, "name" => "Port Townsend" },
        { "id" => 9447883, "name" => "Greenbank" },
        { "id" => 9445016, "name" => "Foulweather Bluff" },
        { "id" => 9447659, "name" => "Everett" },
        { "id" => 9447130, "name" => "Seattle (Elliot)" },
        { "id" => 9446484, "name" => "Tacoma" },
        { "id" => 9446807, "name" => "Olympia (Budd)" }
    ];

    var iStation = 5;

    // initialize the view
    function initialize() {
        CommonView.initialize("tides");

        timer = new Timer.Timer();
        timer.start(method(:moveWindow), 1000 * 60 * 6, true);

        // go get the tidal data from NOAA
        requestTideData();
    }

    function moveWindow() {
        if (fGotData) {
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

    // when the menu button is pressed.  We create a custom menu that lists
    // all of the stations
    function onMenu() {
        resetMenu();
        menu.setTitle("Select Tide Station");
        for (var i = 0; i < stations.size(); i++) {
            addMenuItem(stations[i]["name"]);
        } 
        showMenu();
        return true;
    }

    // called by TidesMenuInput when a new tide station is selected
    function menuItemSelected(stationIndex) {
        iStation = stationIndex;
        requestTideData();
    }

    // load tide data from NOAA
    function requestTideData() {
        minTidalHeight = 9999;
        maxTidalHeight = -9999;
        lastPredictionTime = null;
        lastPredictionHeight = null;
        cTidalHighlightData = 0;
        fGotData = false;
        tideGraphStart = TIDE_GRAPH_START;
        tideNowPoint = TIDE_NOW_POINT;
        errorText = null;

        var now = Time.now();
        var startTimeRange = now.add(new Time.Duration(-TIDE_BATCH_SECONDS * TIDE_BACK_BATCHES));

        // setup all of the global state for our requests first
        for (var i = 0; i < startTimes.size(); i++)
        {
            // compute the time ranges
            var endTimeRange = startTimeRange.add(new Time.Duration(TIDE_BATCH_SECONDS - TIDE_POINT_PERIOD));
            var startInfo = Gregorian.info(startTimeRange, Time.FORMAT_SHORT);
            var endInfo = Gregorian.info(endTimeRange, Time.FORMAT_SHORT);

            // format them as strings and remember them
            startTimes[i] = startInfo.year.format("%04u") + startInfo.month.format("%02u") + startInfo.day.format("%02u") + " " + startInfo.hour.format("%02u") + ":" + startInfo.min.format("%02u");
            endTimes[i] = endInfo.year.format("%04u") + endInfo.month.format("%02u") + endInfo.day.format("%02u") + " " + endInfo.hour.format("%02u") + ":" + endInfo.min.format("%02u");

            // go forward 6 hours
            startTimeRange = endTimeRange.add(new Time.Duration(TIDE_POINT_PERIOD));
        }

        // map to our response functions
        var responseFunctions = [
            method(:response0),
            method(:response1), 
            method(:response2), 
            method(:response3) ];

        // make the requests for each time period
        for (var i = 0; i < startTimes.size(); i++)
        {
            var begin_date = startTimes[i];
            var end_date = endTimes[i];

            System.println("makeRequest()");
            var url = "http://tidesandcurrents.noaa.gov/api/datagetter";
            var station = stations[iStation]["id"];
            System.println("begin_data = " + begin_date + ", end_date = " + end_date + ", station = " + station);
            var headers = {
                "Content-Type" => Comm.REQUEST_CONTENT_TYPE_URL_ENCODED,
                "Accept" => "application/json"
            };
            $.queuedComm.makeWebRequest(
                url, 
                {
                    "begin_date" => begin_date,
                    "end_date" => end_date,
                    "station" => stations[iStation]["id"].toString(),
                    "product" => "predictions",
                    "datum" => "mllw",
                    "units" => "english",
                    "time_zone" => "lst_ldt",
                    "application" => "web_services",
                    "format" => "json"
                },
                {
                    :headers => headers,
                    :method => Comm.HTTP_REQUEST_METHOD_GET,
                    :responseType => Comm.HTTP_RESPONSE_CONTENT_TYPE_JSON
                },
                method(:onReceive),
                i);
                //responseFunctions[i]);
            System.println("makeRequest() done");
            requestsOutstanding++;
        }
    }

    // hacks to allow us to pass another parameter into onRecieve
    function response0(responseCode, data) { onReceive(0, responseCode, data); }
    function response1(responseCode, data) { onReceive(1, responseCode, data); }
    function response2(responseCode, data) { onReceive(2, responseCode, data); }
    function response3(responseCode, data) { onReceive(3, responseCode, data); }

    // onReceive is called async when a batch of data (setup by requestNextTideData) 
    // is received from NOAA.  We process the batch of data received and then either
    // request more data or draw the final graph.
    function onReceive(callIndex, responseCode, data) {
        System.println("onReceive(" + callIndex + ", " + responseCode + ", data);");

        requestsOutstanding--;

        var predictions = null;

        if (responseCode == 200) {
            // this is where all of the good stuff is
            predictions = data["predictions"];

            if (predictions == null) {
                errorText = data["error"];
                if (errorText != null and errorText["message"] != null)
                {
                    errorText = errorText["message"];
                }
                System.println("errorText = " + errorText);
            }
        } else {
            errorText = "response: " + responseCode;
        }

        // save the output of this batch.  We have to convert the output
        // from strings to numbers to avoid using too much memory
        if (errorText == null && predictions != null) {
            var iTidalData = callIndex * TIDE_POINTS_PER_BATCH;
            System.println("iTidalData = " + iTidalData);
    
            for (var i = 0; i < predictions.size(); i++)
            {
                var height = predictions[i]["v"];
                var time = predictions[i]["t"].substring(11, 16);
                var hour = time.substring(0, 2).toNumber();
                var min = time.substring(3, 5).toNumber();
                //System.println(height + "," + time);
                tidalData[iTidalData] = height.toFloat();
                tidalTime[iTidalData] = hour * 60 + min;
                iTidalData++;
            }            
        }

        // when we've recieved all of our responses we are done 
        // requesting data
        if (requestsOutstanding == 0) {
            fGotData = true;
        }

        // if we've finished all requests then process all of the received
        // data
        if (errorText == null && requestsOutstanding == 0)
        {
            // process all predictions
            for (var i = 0; i < tidalData.size(); i++) {
                var height = tidalData[i];
                var hour = tidalTime[i] / 60;
                var min = tidalTime[i] % 60;
                var time = hour.format("%02u") + ":" + min.format("%02u");
                var highlight = null;

                tidalTime[i] = height;

                //System.println(height + "," + time);

                if (height < minTidalHeight) { minTidalHeight = height; }
                if (height > maxTidalHeight) { maxTidalHeight = height; }

                // special times on the graph.  These are off by one since we use the 
                // last... variables for the highlight info
                var highlightColor = null;

                if (i == TIDE_GRAPH_START) {
                    var hour = time.substring(0, 2).toNumber();
                    var min = time.substring(3, 5).toNumber();
                    momentStart = Gregorian.moment({ :hour => hour, :minute => min });
                }

                // detect low/high 
                if (i > 0)
                {
                    var slope = height - lastPredictionHeight;
                    if (lastPredictionSlope < 0 && slope >= 0) { 
                        highlightColor = Graphics.COLOR_DK_RED;
                        highlight = "low"; 
                    }
                    if (lastPredictionSlope >= 0 && slope < 0) { 
                        highlightColor = Graphics.COLOR_DK_GREEN;
                        highlight = "high"; 
                    }
                    lastPredictionSlope = slope;
                }

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
        } 
        
        Ui.requestUpdate();
    }

    // Update the view
    function onUpdate(dc) {
        var bgcolor = Graphics.COLOR_BLACK;
        var fgcolor = Graphics.COLOR_WHITE;

        dc.setColor(bgcolor, bgcolor);
        dc.clear();
        dc.setColor(fgcolor, Graphics.COLOR_TRANSPARENT);

        if (fGotData)
        {
            var center = dc.getWidth() / 2;
            if (errorText == null)
            {
                // draw the tide graph
                var fontHeight = dc.getFontHeight(TIDE_FONT);

                var scaleFactor = TIDE_PIXELS / (maxTidalHeight - minTidalHeight);
                var graphTop = fontHeight + 3;
                var graphBottom = graphTop + TIDE_PIXELS;
                var nowHeight = 0;
                var nowX = 0;
                var tideGraphEnd = tideGraphStart + dc.getWidth();

                for (var x = tideGraphStart; x < tideGraphEnd; x++)
                {
                    var dx = x - tideGraphStart;
                    if (x == tideNowPoint) {
                        dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
                        dc.drawLine(dx, graphTop - 1, dx, graphBottom + 1);
                        nowHeight = tidalData[x];
                        nowX = dx;
                    } else {
                        var y = graphBottom - ((tidalData[x] - minTidalHeight) * scaleFactor);
                        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
                        dc.drawLine(dx, graphTop - 1, dx, y);
                        dc.setColor(Graphics.COLOR_BLUE, Graphics.COLOR_TRANSPARENT);
                        dc.drawLine(dx, y + 1, dx, graphBottom + 1);
                    }
                }

                // station ID
                dc.setColor(fgcolor, Graphics.COLOR_TRANSPARENT);
                dc.drawText(center, 0, TIDE_FONT, stations[iStation]["name"], Graphics.TEXT_JUSTIFY_CENTER);

                // graph start and end times
                var info = Gregorian.utcInfo(momentStart, Time.FORMAT_SHORT);
                var tideGraphStartTime = info.hour.format("%02u") + ":" + info.min.format("%02u");
                var momentEnd = momentStart.add(new Time.Duration(6 * 60 * screenWidth));
                info = Gregorian.utcInfo(momentEnd, Time.FORMAT_SHORT);
                var tideGraphEndTime = info.hour.format("%02u") + ":" + info.min.format("%02u");
                dc.setColor(fgcolor, Graphics.COLOR_TRANSPARENT);
                dc.drawText(0, graphBottom, TIDE_FONT, tideGraphStartTime, Graphics.TEXT_JUSTIFY_LEFT);
                dc.drawText(screenWidth - 1, graphBottom, TIDE_FONT, tideGraphEndTime, Graphics.TEXT_JUSTIFY_RIGHT);
                dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
                dc.drawText(nowX, graphBottom, TIDE_FONT, nowHeight.format("%2.1f") + "ft", Graphics.TEXT_JUSTIFY_LEFT);

                // tide time periods
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
                if (cTidalHighlightData > 4) {
                    clockSpeedFont = TIDE_FONT;
                } else {
                    clockSpeedFont = Graphics.FONT_MEDIUM;
                }
            } else {
                var y = 0;
                var font = Graphics.FONT_LARGE;
                y += dc.getFontHeight(font) + 4;
                dc.drawText(dc.getWidth() / 2, y, font, "Loading", Graphics.TEXT_JUSTIFY_CENTER);    
                y += dc.getFontHeight(font) + 4;
                dc.drawText(dc.getWidth() / 2, y, font, "Failure", Graphics.TEXT_JUSTIFY_CENTER);    
                y += dc.getFontHeight(font) + 4;
                drawCenteredTextWithWordWrap(dc, y, TIDE_FONT, errorText);
            }
        } else {
            var y = 0;
            var font = Graphics.FONT_LARGE;
            y += dc.getFontHeight(font) + 4;
            dc.drawText(dc.getWidth() / 2, y, font, "Loading", Graphics.TEXT_JUSTIFY_CENTER);    
            y += dc.getFontHeight(font) + 4;
            dc.drawText(dc.getWidth() / 2, y, font, "Tides", Graphics.TEXT_JUSTIFY_CENTER);    
            y += dc.getFontHeight(font) + 4;
            var dots = "";
            for (var i = 0; i < requestsOutstanding; i++) { dots = dots + "."; }
            dc.drawText(dc.getWidth() / 2, y, font, dots, Graphics.TEXT_JUSTIFY_CENTER);    
        }
        CommonView.onUpdate(dc);
    }
}
