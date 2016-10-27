using Toybox.WatchUi as Ui;
using Toybox.Time as Time;
using Toybox.Time.Gregorian as Gregorian;
using Toybox.Lang as Lang;
using Toybox.System as System;
using Toybox.Timer as Timer;
using Toybox.Position as Position;
using Toybox.Attention as Attention;
using Toybox.Communications as Comm;

//
// WindsView displays Puget Sound wind information that is downloaded from
// Bob Hall's awesome obs website: http://b.obhall.com/obs
//
class WindsView extends CommonView {
    // this is all hardcoded to the vivoactive HR screen
    const SPEED_FONT = Graphics.FONT_NUMBER_HOT;
    const TITLE_FONT = Graphics.FONT_XTINY;
    const DIR_FONT = Graphics.FONT_MEDIUM;
    const WINDTIME_FONT = Graphics.FONT_XTINY;

    //
    // windData gets the raw data that is downloaded from the internet
    // Fields:
    //   station_name -- What is the name of the wind station?
    //   wind_speed -- current wind speed
    //   wind_direction -- current wind direction
    //   time -- the time that this wind speed was recorded
    //   
    var windData = [];
    // hack to make it center on Seattle initially
    var iWindData = 3;

    var timer = null;

    //
    // initialize the view
    //
    function initialize() {
        CommonView.initialize("wind");

        // override the clock font
        clockSpeedFont = WINDTIME_FONT;

        // setup our refresh timer
        timer = new Timer.Timer();

        // go get the tidal data from bob
        requestWindData();
    }

    //
    // called when the menu key is hit.  Our menu lists all of the wind
    // stations and lets a user pick one.
    //
    function onMenu() {
        resetMenu();
        menu.setTitle("Select Wind Station");
        for (var i = 0; i < windData.size(); i++) {
            addMenuItem(windData[i]["station_name"]);
        } 
        showMenu();
        return true;
    }

    //
    // called when a menu item is selected
    // 
    // index -- the selected wind station
    //
    function menuItemSelected(index) {
        iWindData = index;
        Ui.requestUpdate();
    }

    //
    // cycle through the wind stations by swiping
    //
    function onSwipeUp() {
        if ((windData != null) && (windData.size() > 0)) {
            iWindData = (iWindData + 1) % windData.size();
            Ui.requestUpdate();
        }
    }

    //
    // used to cycle through wind stations
    //
    function onSwipeDown() {
        if ((windData != null) && (windData.size() > 0)) {
            iWindData--;
            if (iWindData < 0) { iWindData = windData.size() - 1; }
            Ui.requestUpdate();
        }
    }

    //
    // Make a web request to get the wind data from the internet
    //
    function requestWindData() {
        System.println("makeRequest()");
        var url = "http://b.obhall.com/obs/";
        var headers = {
            "Content-Type" => Comm.REQUEST_CONTENT_TYPE_URL_ENCODED,
            "Accept" => "application/json"
        };
        Comm.makeWebRequest(
            url, 
            { },
            {
                :headers => headers,
                :method => Comm.HTTP_REQUEST_METHOD_GET,
                :responseType => Comm.HTTP_RESPONSE_CONTENT_TYPE_JSON
            },
            method(:onReceive));
        System.println("makeRequest() done");
    }

    //
    // Callback for requestWindData
    //
    // responseCode -- HTTP response code when doing the JSON request
    // data -- the raw data that is received
    //
    function onReceive(responseCode, data) {
        System.println("onReceive(): " + responseCode);

        var predictions = null;
        var timerSeconds = 600;

        if (responseCode == Comm.BLE_QUEUE_FULL) {
            timerSeconds = 5;
        }
        if (responseCode == 200) {
            windData = data;
            System.println(windData);
        }

        // setup a refresh timer
        timer.start(method(:requestWindData), timerSeconds * 1000, false);
        Ui.requestUpdate();
    }

    //
    // Update the view
    //
    function onUpdate(dc) {
        var bgcolor = Graphics.COLOR_BLACK;
        var fgcolor = Graphics.COLOR_WHITE;

        dc.setColor(bgcolor, bgcolor);
        dc.clear();
        dc.setColor(fgcolor, Graphics.COLOR_TRANSPARENT);

        var y = 0;
        var center = screenWidth / 2;
        var cellHeight = 0;

        dc.setColor(bgcolor, bgcolor);
        dc.clear();
        dc.setColor(fgcolor, Graphics.COLOR_TRANSPARENT);

        if ((windData != null) && (windData.size() > 0)) {
            // The rendering is tweaked to get 3 wind stations onto the 
            // screen at once.  
            for (var i = iWindData; i < windData.size() && y < screenHeight - cellHeight; i++)
            {
                // this just tightens up things a tad
                y--;

                dc.drawLine(0, y-1, screenWidth, y-1);
                // what we'll show
                var wind = windData[i];
                var speed = "---";
                var dir = "---";
                var windtime = "---";
                var stationName = "---";

                // save process the parameters (don't trust the JSON)
                if (wind != null) {
                    try {
                        stationName = wind["station_name"];
                        speed = wind["wind_speed"];
                        if (speed != null) { speed = speed.format("%.1f"); } else { speed = "---"; }
                        dir = wind["wind_direction"];
                        if (dir == null) { dir = "---"; }
                        windtime = wind["time"].substring(12, 17) + wind["time"].substring(20, 24);
                    } catch (e) {
                        System.println(e);
                    }
                }

                // render it.  

                // station ID on top
                dc.drawText(center, y, TITLE_FONT, stationName, Graphics.TEXT_JUSTIFY_CENTER);
                y += dc.getFontHeight(TITLE_FONT) - 7;
                //y += drawCenteredTextWithWordWrap(dc, y, TITLE_FONT, stationName) * dc.getFontHeight(TITLE_FONT);

                // show speed, dir, time left to right
                dc.drawText(85, y, SPEED_FONT, speed, Graphics.TEXT_JUSTIFY_RIGHT);

                // time
                dc.drawText(90, y + 4, WINDTIME_FONT, windtime, Graphics.TEXT_JUSTIFY_LEFT);

                y += dc.getFontHeight(SPEED_FONT);

                // direction
                dc.drawText(90, y - dc.getFontHeight(DIR_FONT) - 4, DIR_FONT, dir, Graphics.TEXT_JUSTIFY_LEFT);

                if (i == iWindData) { cellHeight = y; }
            }
        } else {
            var y = 0;
            var font = Graphics.FONT_LARGE;
            y += dc.getFontHeight(font) + 4;
            dc.drawText(dc.getWidth() / 2, y, font, "Loading", Graphics.TEXT_JUSTIFY_CENTER);    
            y += dc.getFontHeight(font) + 4;
            dc.drawText(dc.getWidth() / 2, y, font, "Wind Stations", Graphics.TEXT_JUSTIFY_CENTER);    
            y += dc.getFontHeight(font) + 4;
        }
        CommonView.onUpdate(dc);
    }
}
