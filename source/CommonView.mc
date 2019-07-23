using Toybox.WatchUi as Ui;
using Toybox.Time as Time;
using Toybox.Time.Gregorian as Gregorian;
using Toybox.Lang as Lang;
using Toybox.System as System;
using Toybox.Timer as Timer;
using Toybox.Position as Position;
using Toybox.Attention as Attention;
using Toybox.Communications as Comm;

var speed = -1;
var heading = -1;
var session = null;
var gpsAccuracy = 0;

class CommonView extends Ui.View {
    // screen width
    var screenWidth;
    var quarterWidth;
    var screenHeight;
    var cMenuItems = 0;
    var menu = null;
    var viewName;
    var highSpeedRefresh = false;
    var clockSpeedFont = Graphics.FONT_MEDIUM;
    var updateTimer;

    // initialize the view
    function initialize(viewName) {
        self.viewName = viewName;   
        var settings = System.getDeviceSettings();
        self.screenWidth = settings.screenWidth;
        self.screenHeight = settings.screenHeight;
        self.quarterWidth = self.screenWidth / 4;   
        System.println("screenWidth = " + screenWidth);
        System.println("screenHeight = " + screenHeight);
        View.initialize();
    }

    function reduceMemory() {
        System.println("reduce memory: " + viewName);
    }

    // called when the user clicks on the screen
    function screenTap(evt) {
        return true;
    }

    function onSwipeUp() 
    {
        return onDownKey();
    }

    function onSwipeDown() 
    {
        return onUpKey();
    }

    function onEscKey() 
    {
        return quitDialog();
    }

    function onEnterKey() 
    {
        return true;
    }

    function onDownKey() 
    {
        return true;
    }

    function onUpKey() 
    {
        return true;
    }

    function quitDialog() {
        var dialog = new Ui.Confirmation("Really quit?");
        Ui.pushView(dialog, new ConfirmQuitDelegate(), Ui.SLIDE_IMMEDIATE);
        return true;
    }

    function errorDialog(errorText) {
        var dialog = new Ui.Confirmation(errorText);
        Ui.pushView(dialog, new Ui.ConfirmationDelegate(), Ui.SLIDE_IMMEDIATE);
    }

    // called when the menu key is hit
    function onMenu() 
    {
        menu = new Ui.Menu2({:title => "Sailing"});
        self.addViewMenuItems(menu);
        $.inputDelegate.addViewMenuItems(menu);
        menu.addItem(new Ui.MenuItem("Quit", "Quit Sailing App", :quitMenuItem, {}));

        var delegate = new MyMenu2Delegate(self);
        Ui.pushView(menu, delegate, Ui.SLIDE_UP);

        return true;
    }

    // subclasses can use this to add custom entries into the menu
    function addViewMenuItems(menu)
    {
    }

    function viewMenuItemSelected(symbol, item)
    {
        return false;
    }

    // called when a menu item has been selected
    function menuItemSelected(item)
    {
        var symbol = item.getId();
        if ($.inputDelegate.viewMenuItemSelected(symbol, item))
        {
            System.println("$.inputDelegate.viewMenuItemSelected returned true");
        }
        else if (self.viewMenuItemSelected(symbol, item))
        {
            System.println("self.viewMenuItemSelected returned true");
        }
        else if (symbol == :quitMenuItem)
        {
            System.println("quit menu item selected");
            Ui.popView(Ui.SLIDE_DOWN);
            quitDialog();
        }
    }

    // called when a menu item is selected
    function setStation(stationIndex) {
        iWindData = stationIndex;
        menu = null;
        Ui.requestUpdate();
    }

    // Load your resources here
    function onLayout(dc) {
    }

    // called by SailingAppDelegate on GPS events
    function onPositionUpdate(info) {
    }

    // Called when this View is brought to the foreground. Restore
    // the state of this View and prepare it to be shown. This includes
    // loading resources into memory.
    function onShow() {
        System.println("showing: " + viewName);
        updateTimer = new Timer.Timer();
        if (highSpeedRefresh) {
            // onUpdate every 250ms
            updateTimer.start(method(:refreshView), 250, true);
        } else {
            // onUpdate every 10sec
            updateTimer.start(method(:refreshView), 10000, true);
        }
        return true;
    }

    function setValueText(id, text)
    {
        var d = Ui.View.findDrawableById(id);
        //System.println("setValueText(" + id + ", " + text + ")");
        if (text == null)
        {
            text = "";
        }
        if (d != null)
        {
            d.setText(text);
        }
    }

    // Update the view
    function onUpdate(dc) {
        Ui.View.onUpdate(dc);
        var view;

        // speed label
        view = Ui.View.findDrawableById("SogValue");
        if (view != null)
        {
            if ($.speed == -1)
            {
                view.setText("--");
            }
            else
            {
                var knots = $.speed * 1.94384449;
                var speedText = knots.format("%02.1f");
                var sogUnits = Ui.View.findDrawableById("SogUnitsLabel");
                if (sogUnits == null)
                {
                    speedText = speedText + "kts";
                }
                view.setText(speedText);
            }
        }

        // heading label
        view = Ui.View.findDrawableById("CogValue");
        if (view != null)
        {
            var headingText = ($.heading * 57.2957795);
            if (headingText < 0) { headingText += 360; }
            headingText = headingText.format("%02.0f");
            view.setText(headingText);
        }

        // clock label no seconds
        view = View.findDrawableById("ClockValue");
        if (view != null)
        {
            var now = Time.now();
            var timestruct = Gregorian.info(now, Time.FORMAT_SHORT);
            var clockTime = timestruct.hour.format("%02u") + ":" + timestruct.min.format("%02u");
            view.setText(clockTime);
        }

        // clock label with seconds
        view = View.findDrawableById("ClockValueWithSeconds");
        if (view != null)
        {
            var now = Time.now();
            var timestruct = Gregorian.info(now, Time.FORMAT_SHORT);
            var clockTime = timestruct.hour.format("%02u") + ":" + timestruct.min.format("%02u") + ":" + timestruct.sec.format("%02u");
            view.setText(clockTime);
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
