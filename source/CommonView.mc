using Toybox.WatchUi as Ui;
using Toybox.Time as Time;
using Toybox.Time.Gregorian as Gregorian;
using Toybox.Lang as Lang;
using Toybox.System as System;
using Toybox.Timer as Timer;
using Toybox.Position as Position;
using Toybox.Attention as Attention;
using Toybox.Communications as Comm;

const menuSymbols = [
    :menuItem0,
    :menuItem1,
    :menuItem2,
    :menuItem3,
    :menuItem4,
    :menuItem5,
    :menuItem6,
    :menuItem7,
    :menuItem9,
    :menuItem10,
    :menuItem11,
    :menuItem12,
    :menuItem13,
    :menuItem14,
    :menuItem15,
    :menuItem16,
    :menuItem17,
    :menuItem18,
    :menuItem19,
    :menuItem20,
    :menuItem21,
    :menuItem22,
    :menuItem23,
    :menuItem24,
    :menuItem25,
    :menuItem26,
    :menuItem27,
    :menuItem28,
    :menuItem29,
    :menuItem30,
    :menuItem31,
    :menuItem32,
    :menuItem33,
    :menuItem34,
    :menuItem35,
    :menuItem36,
    :menuItem37,
    :menuItem38,
    :menuItem39
    ];

var speed = -1;
var heading = -1;
var session = null;
var gpsAccuracy = 0;

class CommonView extends Ui.View {
    // screen width
    var screenWidth = 148;
    var quarterWidth;
    var screenHeight;
    var cMenuItems = 0;
    var menu = null;
    var viewName;
    var showSeconds = false;
    var showClock = true;
    var showSpeed = true;
    var clockSpeedFont = Graphics.FONT_MEDIUM;
    var updateTimer;

    // initialize the view
    function initialize(viewName) {
        self.viewName = viewName;
        View.initialize();
    }

    function reduceMemory() {
        System.println("reduce memory: " + viewName);
    }

    // called when the user clicks on the screen
    function screenTap(evt) {
        return true;
    }

    function onSwipeUp() {
        return true;
    }

    function onSwipeDown() {
        return true;
    }

    function onEscKey() {
        return onSwipeDown();
    }

    function onEnterKey() {
        return onSwipeUp();
    }

    function quitDialog() {
        var dialog = new Ui.Confirmation("Really quit?");
        Ui.pushView(dialog, new ConfirmQuitDelegate(), Ui.SLIDE_IMMEDIATE);
    }

    function errorDialog(errorText) {
        var dialog = new Ui.Confirmation(errorText);
        Ui.pushView(dialog, new Ui.ConfirmationDelegate(), Ui.SLIDE_IMMEDIATE);
    }

    // called by onMenu to start a new menu
    function resetMenu() {
        menu = new Ui.Menu();
        cMenuItems = 0;
    }

    // called for each menu item to be shown to the user
    function addMenuItem(text) {
        menu.addItem(text, $.menuSymbols[cMenuItems]);
        cMenuItems++;
        if (cMenuItems >= menuSymbols.size()) {
            System.println("menu full!!!");
            cMenuItems--;
        }
    }

    function maxMenuItems() 
    {
        return $.menuSymbols.size();
    }

    // called after all calls to addMenuItem
    function showMenu() {
        Ui.pushView(menu, new CommonMenuInput(self), Ui.SLIDE_UP);
    }

    // called when the menu key is hit
    function onMenu() {
        // example for subclasses to use:
        //resetMenu();
        //menu.setTitle("Select Wind Station");
        //for (var i = 0; i < windData.size(); i++) {
        //    menu.addItem(windData[i]["station_name"], $.menuSymbols[i]);
        //} 
        //showMenu();
        return true;
    }

    // called when a menu item is selected
    function setStation(stationIndex) {
        iWindData = stationIndex;
        menu = null;
        Ui.requestUpdate();
    }


    // Load your resources here
    function onLayout(dc) {
        screenWidth = dc.getWidth();
        screenHeight = dc.getHeight();
        quarterWidth = dc.getWidth() / 4;
    }

    // Called when this View is brought to the foreground. Restore
    // the state of this View and prepare it to be shown. This includes
    // loading resources into memory.
    function onShow() {
        System.println("showing: " + viewName);
        updateTimer = new Timer.Timer();
        if (showSeconds) {
            // onUpdate every 100ms
            updateTimer.start(method(:refreshView), 100, true);
        } else {
            // onUpdate every 10sec
            updateTimer.start(method(:refreshView), 10000, true);
        }
        return true;
    }

    // Update the view
    function onUpdate(dc) {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);

        if (showSpeed) {
            // speed
            if ($.speed != -1) {
                var knots = $.speed * 1.94384449;
                var speedText = knots.format("%02.1f") + "kts";
                dc.drawText(0, dc.getHeight() - dc.getFontHeight(clockSpeedFont), clockSpeedFont, speedText, Graphics.TEXT_JUSTIFY_LEFT);
            }
        }

        // clock
        if (showClock) {
            var now = Time.now();
            var timestruct = Gregorian.info(now, Time.FORMAT_SHORT);
            var clocktime = timestruct.hour.format("%02u") + ":" + timestruct.min.format("%02u");
            if (showSeconds) {
                clocktime = clocktime + ":" + timestruct.sec.format("%02u");
            }
            dc.drawText(screenWidth - 1, dc.getHeight() - dc.getFontHeight(clockSpeedFont), clockSpeedFont, clocktime, Graphics.TEXT_JUSTIFY_RIGHT);
        }
    }

    function refreshView() {
        Ui.requestUpdate();
    }

    function appendToArray(a, i)
    {
        var newA = new[a.size() + 1];
        for (var i = 0; i < a.size(); i++)
        {
            newA[i] = a[i];
        }
        newA[a.size()] = i;
        return newA;
    }

    //
    // wrap text to fit the screen.  Returns a number of lines, none
    // of which are wider than the screen width using this font.
    //
    // this is really ugly, but works.  too many special cases.
    //
    function wordWrap(dc, font, text) 
    {
        var lines = [];
        var width = dc.getTextWidthInPixels(text, font);
        if (width > screenWidth) 
        {
            var done = 0;
            do 
            {
                var keep = "";
                var space = -1;
                var subwidth = -1;
                do 
                {
                    if (space != -1) {
                        keep = keep + " " + text.substring(0, space);
                        text = text.substring(space + 1, text.length());
                    }
                    space = text.find(" ");
                    if (space == null) {
                        done = 1;
                    } else {
                        subwidth = dc.getTextWidthInPixels(keep + " " + text.substring(0, space), font);
                    }
                } 
                while (done == 0 && subwidth < screenWidth);
                keep = keep.substring(1, keep.length());
                if (done)
                {
                    var both = keep + " " + text;
                    if (dc.getTextWidthInPixels(both, font) < screenWidth)
                    {
                        text = both;
                        keep = "";
                    } 
                }
                if (keep.length() > 0) { lines = appendToArray(lines, keep); }
            } 
            while (done == 0);
            lines = appendToArray(lines, text);
        }
        else
        {
            lines = [ text ];
        }

        return lines;
    }

    //
    // This does a nice job of drawing a set of fields on the watch display
    //
    // inputs:
    // dc -- drawing context
    // y -- y offset that this can start using
    // fields -- array of fields to draw
    // fieldLabels -- text label for each field (use 4 or less characters)
    // fieldUnits -- unit text for each field (use 4 or less characters)
    // fieldFonts -- font for each field
    // outputs:
    // updated y
    //
    function drawFields(dc, y, fields, fieldLabels, fieldUnits, fieldFonts)
    {
        dc.drawLine(0, y, screenWidth, y);
        for (var i = 0; i < fields.size(); i++) {
            dc.drawText(0, y, Graphics.FONT_XTINY, fieldLabels[i], Graphics.TEXT_JUSTIFY_LEFT);
            y += dc.getFontHeight(Graphics.FONT_XTINY) / 3;
            dc.drawText(quarterWidth * 2, y, fieldFonts[i], fields[i], Graphics.TEXT_JUSTIFY_CENTER);
            dc.drawText(screenWidth - 1, y + dc.getFontHeight(fieldFonts[i]) - dc.getFontHeight(Graphics.FONT_XTINY) + 3, Graphics.FONT_XTINY, fieldUnits[i], Graphics.TEXT_JUSTIFY_RIGHT);
            y += dc.getFontHeight(fieldFonts[i]) + 5;
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawLine(0, y, screenWidth, y);
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        }

        return y;
    }

    //
    // This does a nice job of drawing a set of fields that use half of the width of the display
    //
    // inputs:
    // dc -- drawing context
    // x -- x offset of the left side to use
    // y -- y offset that this can start using
    // fields -- array of fields to draw
    // fieldLabels -- text label for each field (use 4 or less characters)
    // fieldUnits -- unit text for each field (use 4 or less characters)
    // fieldFonts -- font for each field
    // outputs:
    // updated y
    //
    function drawHalfWidthFields(dc, x, y, fields, fieldLabels, fieldFonts)
    {
        dc.drawLine(x, y, x + screenWidth / 2, y);
        for (var i = 0; i < fields.size(); i++) {
            dc.drawText(x, y, Graphics.FONT_XTINY, fieldLabels[i], Graphics.TEXT_JUSTIFY_LEFT);
            y += dc.getFontHeight(Graphics.FONT_XTINY) - 3;
            dc.drawText(x + quarterWidth, y, fieldFonts[i], fields[i], Graphics.TEXT_JUSTIFY_CENTER);
            y += dc.getFontHeight(fieldFonts[i]);
            dc.drawLine(0, y, screenWidth, y);
        }

        return y;
    }

    // Called when this View is removed from the screen. Save the
    // state of this View here. This includes freeing resources from
    // memory.
    function onHide() {
        System.println("hiding: " + viewName);

        updateTimer.stop();
        updateTimer = null;

        return true;
    }

    function ErrorDialog(text)
    {
        new Confirmation(text);
    }

    //
    // Map the GPS accuracy into a color
    //
    function GpsAccuracyColor(gpsAccuracy)
    {
        if ($.gpsAccuracy < 2) 
        {
            return Graphics.COLOR_RED;
        } 
        else if ($.gpsAccuracy == 2) 
        {
            return Graphics.COLOR_YELLOW;
        } 
        else 
        {
            return Graphics.COLOR_GREEN;
        }
    }

    //
    // Make a HTTP client request to get some JSON from the internet
    //
    // input:
    //  url -- url to request from
    //  callback -- callback to call when the request is finished
    //
    function httpGetJson(url, callback)
    {
        System.println("common: httpGetJson() to " + url);
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
            method(callback));
        System.println("common: httpGetJson() done");
    }

}

class CommonMenuInput extends Ui.MenuInputDelegate {
    var view;

    function initialize(viewPointer) {
        view = viewPointer;
        MenuInputDelegate.initialize();
    }

    function onMenuItem(symbol) {
        for (var i = 0; i < menuSymbols.size(); i++)
        {
            if (menuSymbols[i] == symbol) {
                System.println("menu item selected: " + i);
                view.menuItemSelected(i);
            }
        }
    }
    
    function onBack() {
        Ui.popView(Ui.SLIDE_DOWN);
    }
}
