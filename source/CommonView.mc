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
    :menuItem8
    ];

var speed = -1;
var heading = -1;
var session = null;
var gpsAccuracy = 0;

class CommonView extends Ui.View {
    // this is all hardcoded to the vivoactive HR screen
    const TIME_FONT = Graphics.FONT_MEDIUM;

    // screen width
    var screenWidth = 148;
    var screenHeight;
    var cMenuItems = 0;
    var menu = null;
    var viewName;
    var showSeconds = false;
    var showClock = true;
    var showSpeed = true;
    var clockSpeedFont = TIME_FONT;
    var updateTimer;

    // initialize the view
    function initialize(viewName) {
        self.viewName = viewName;
        View.initialize();
    }

    // called when the user clicks on the screen
    function screenTap(evt) {
        return true;
    }

    // when the user hits the enter key
    function onEnterKey() {
        return true;
    }

    function onSwipeUp() {
        return true;
    }

    function onSwipeDown() {
        return true;
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

    // Quick and dirty word wrap for long titles.  
    // It makes the assumption that what doesn't fit in one line will 
    // fit in two.  Things will get ugly beyond that.
    function drawCenteredTextWithWordWrap(dc, y, font, text) {
        var lines = 1;
        var width = dc.getTextWidthInPixels(text, font);
        var keep = "";
        if (width > screenWidth) {
            var space = -1;
            var subwidth = -1;
            var done = 0;
            do {
                if (space != -1) {
                    keep = keep + " " + text.substring(0, space);
                    text = text.substring(space + 1, text.length());
                }
                System.println("keep=." + keep + ".");
                System.println("text=." + text + ".");
                space = text.find(" ");
                if (space == null) {
                    done = 1;
                } else {
                    subwidth = dc.getTextWidthInPixels(keep + " " + text.substring(0, space), font);
                }
                System.println("subwidth=" + subwidth + " " + screenWidth);
            } while (done == 0 && subwidth < screenWidth);
            text = keep.substring(1, keep.length()) + "\n" + text;
            lines++;
        }
        dc.drawText(screenWidth / 2, y, font, text, Graphics.TEXT_JUSTIFY_CENTER);
        return lines;
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
