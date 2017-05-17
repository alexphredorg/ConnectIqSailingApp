/*
using Toybox.WatchUi as Ui;
using Toybox.Time as Time;
using Toybox.Time.Gregorian as Gregorian;
using Toybox.Lang as Lang;
using Toybox.System as System;
using Toybox.Timer as Timer;
using Toybox.Position as Position;
using Toybox.Attention as Attention;
using Toybox.Communications as Comm;

class DebugView extends CommonView {
    //
    // initialize the view
    //
    function initialize() {
        CommonView.initialize("debug");
    }

    var info = null;

    //
    // called when the position is updated by GPS. 
    // 
    function onPositionUpdate(info) {
        self.info = info;
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

        var position = [ 0, 0 ];
        if (self.info != null)
        {
            position = self.info.position.toDegrees();
        }

        self.drawFields(
            dc, 0, 
            [ position[0], position[1] ], 
            [ "lat", "lon" ], 
            [ "deg", "deg" ], 
            [ Graphics.FONT_SMALL, Graphics.FONT_SMALL ]);

        CommonView.onUpdate(dc);
    }
}
*/
