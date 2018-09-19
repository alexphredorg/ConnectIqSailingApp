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
using Toybox.Math as Math;


//
// WindsView displays Puget Sound wind information that is downloaded from
// Bob Hall's awesome obs website: http://b.obhall.com/obs
//
class MarksView extends CommonView {
    var folderNames = null; 
    var marks = null; 

    // state variables used to render the view
    var selectedMark = -1;
    var selectedFolder = -1;
    var folderMarks = null;
    var speed = 0;
    var gpsAccuracy = 0;
    var cog = 0;
    var position = null;
    var desiredPosition = [ 0, 0 ];
    var markName = "";
    var markShortname = "";
    var menuLevel = 0;
    var reloadFromWeb = false;
    var refreshCount = 1;
    var shrunk = false;
    var loadError = null;
    var loadErrorCode = null;

    //
    // initialize the view
    //
    function initialize() {
        showSeconds = true;
        CommonView.initialize("marks");
        loadMarks();
        newMarkSelected();
    }

    //
    // Save our mark data to the object store
    //
    function saveMarks()
    {
        var app = App.getApp();
        app.setProperty("folderNames", folderNames);
        app.setProperty("marks", marks);
        app.setProperty("selectedMark", selectedMark);
        app.setProperty("selectedFolder", selectedFolder);
        reloadFromWeb = false;
    }

    //
    // Clear the stored set of marks
    function defaultMarks()
    {
        folderNames = [];
        marks = [];
        selectedMark = -1;
        selectedFolder = -1;
        folderMarks = null;
    }

    //
    // Load marks from the object store.  This will return no marks if
    // the object store doesn't work.
    //
    function loadMarks()
    {
        var app = App.getApp();
        // DEBUG app.clearProperties();
        folderNames = app.getProperty("folderNames");
        marks = app.getProperty("marks");
        selectedMark = app.getProperty("selectedMark");
        selectedFolder = app.getProperty("selectedFolder");
        System.println("selectedFolder = " + selectedFolder);
        System.println("selectedMark = " + selectedMark);
        if (folderNames == null || marks == null)
        {
            defaultMarks();
        }
        else
        {
            if (selectedFolder != -1) {
                folderMarks = marks[selectedFolder];
            }
        }
        shrunk = false;
        dumpMarks();
    }

    // debug only
    function dumpMarks()
    {
        for (var i = 0; i < marks.size(); i++)
        {
            var folder = marks[i];
            System.println("Folder: " + folderNames[i]);
            for (var j = 0; j < folder.size(); j++)
            {
                var mark = folder[j];
                var name = mark["n"];
                var lat = mark["y"];
                var lon = mark["x"];
                //if (lat instanceof Toybox.Lang.String) { lat = convertDegreesMinutes(lat); }
                //if (lon instanceof Toybox.Lang.String) { lon = convertDegreesMinutes(lon); }
                System.println("{ :name=>\"" + name + "\", :lat=>" + lat + ", :lon=>" + lon + " },");
            }
        }
        System.println("selectedMark = " + selectedMark);
        System.println("selectedFolder = " + selectedFolder);
        System.println("usedMemory: " + System.getSystemStats().usedMemory);
    }

    //
    // called when the position is updated by GPS. 
    // 
    function onPositionUpdate(info) {
        self.speed = info.speed;
        self.gpsAccuracy = info.accuracy;
        self.cog = info.heading;
        if (info.position == null)
        {
            self.position = null;
        }
        else
        {
            self.position = info.position.toDegrees();
        }
    }

    function reduceMemory() {
        System.println("marks: reduceMemory");
        defaultMarks();
        shrunk = true;
    }

    function recoverFromReduceMemory() {
        System.println("marks: recoverFromReduceMemory");
        if (shrunk) {
            loadMarks();
        }
    }

    //
    // Make a web request to get the wind data from the internet
    //
    function requestMarkDataFromCaltopo() {
        var app = App.getApp();
        app.reduceMemory();
        var calTopoId = app.getProperty("calTopoId");
        var url = "http://www.phred.org:18266/CalTopo/" + calTopoId;

        loadError = null;
        loadErrorCode = null;

        defaultMarks();
        System.println("marks: makeRequest() to " + url);
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
        System.println("marks: makeRequest() done");
    }

    //
    // Callback for requestMarkData
    //
    // responseCode -- HTTP response code when doing the JSON request
    // data -- the raw data that is received
    //
    function onReceive(responseCode, data) 
    {
        System.println("marks: onReceive(): " + responseCode);

        if (responseCode == 200) 
        {
            if (data["groups"] != null && data["groups"] instanceof Toybox.Lang.Array)
            {
                var groupCount = data["groups"].size();
                System.println("group count: " + groupCount);
                for (var i = 0; i < groupCount; i++)
                {
                    var g = data["groups"][i];
                    var name = "group " + i;
                    var marks = [];
                    if (g instanceof Toybox.Lang.Dictionary) {
                        if (g["name"] != null && g["name"] instanceof Toybox.Lang.String)
                        {
                            name = g["name"];
                        }
                        if (g["marks"] != null && g["marks"] instanceof Toybox.Lang.Array)
                        {
                            ParseMarks(name, g["marks"]);
                            marks = g["marks"];
                        }
                    }
                }
            }

            // save out the new marks to the object store
            saveMarks();
            shrunk = false;
        }
        else
        {
            // an error occured, reload our old marks
            loadMarks();

            // remember the error
            var app = App.getApp();
            var calTopoId = app.getProperty("calTopoId");
            loadError = "Invalid CalTopoID";
            loadErrorCode = responseCode;
        }

        onMenu();
    }

    //
    // parse the marks from json downloaded from the web.  This does some basic checking to make
    // sure that the data is valid.
    // 
    // inputs:
    //   folderName -- the group/folder name for this set of marks
    //   marksArray -- an array of marks
    //
    function ParseMarks(folderName, marksArray)
    {
        var n = "n";
        var x = "x";
        var y = "y";

        System.println("Parsing marks folder: " + folderName);
        // parse the mark data that we received
        var markIndex = 0;
        var folder = new [marksArray.size()];
        for (var i = 0; i < marksArray.size(); i++)
        {
            var mark = marksArray[i];
            System.println("Parsing mark: " + mark);
            System.println("usedMemory: " + System.getSystemStats().usedMemory);
            if (mark instanceof Toybox.Lang.Dictionary)
            {
                var o = new Lang.Object();
                System.println(o.toString());
                o = null;
                var name = null;
                var lat = -1;
                var lon = -1;

                if (mark["n"] != null && mark["n"] instanceof Toybox.Lang.String) { name = mark["n"]; }   
                if (mark["lat"] != null && mark["lat"] instanceof Toybox.Lang.Float) { lat = mark["lat"]; }   
                if (mark["lon"] != null && mark["lon"] instanceof Toybox.Lang.Float) { lon = mark["lon"]; }   

                if (lat != -1 && lon != -1 && name != null) {
                    folder[markIndex] = { n=>name, y=>lat, x=>lon };
                    System.println("new mark: " + folder[markIndex]);
                    markIndex++;
                }
            }
        }

        if (markIndex > 0)
        {
            System.println("Using downloaded marks");
            // if we couldn't parse some marks then reduce the size of this folder
            if (markIndex != folder.size())
            {
                var newFolder = new [markIndex];
                for (var i = 0; i < markIndex; i++) { newFolder[i] = folder[i]; }
                folder = newFolder;
            }

            // splice this folder into the existing data structure of marks
            var newFolderNames = new[folderNames.size() + 1];
            for (var i = 0; i < folderNames.size(); i++) { newFolderNames[i] = folderNames[i]; }
            newFolderNames[folderNames.size()] = folderName;

            var newMarks = new [marks.size() + 1];
            for (var i = 0; i < marks.size(); i++) { newMarks[i] = marks[i]; }
            newMarks[marks.size()] = folder;

            System.println("Added new marks to folder: " + folderName);

            marks = newMarks;
            folderNames = newFolderNames;
        }
    }

    //
    // % modulo operator in monkey C only supports ints.  This does the same thing for 
    // floats
    //
    function fmod(dividend, divisor) {
        var n = (dividend / divisor).toNumber();
        return dividend - (n * divisor);
    }

    // 
    // measure the distance and direction between two points on earth
    // 
    // point1: array of lat, lon for the first point
    // point2: array of lat, lon for the second point
    // returns: array of distance and angle from point1 to point2
    //
    function measureDistance(point1, point2)
    {
        System.println("point1 = " + point1[0] + "," + point1[1]);
        System.println("point2 = " + point2[0] + "," + point2[1]);

        var pi = Math.PI;
        var lat1 = (point1[0] * (pi / 180));
        var lon1 = (point1[1] * (pi / 180));
        var lat2 = (point2[0] * (pi / 180));
        var lon2 = (point2[1] * (pi / 180));

        var R = 3440; // nm
        var t1 = lat1;
        var t2 = lat2;
        var dt = lat2 - lat1;
        var ds = lon2 - lon1;

        var foo = Math.sin(lon2 - lon1);

        var angle =
            fmod(
                Math.atan2(
                    Math.sin(lon2 - lon1) * Math.cos(lat2),
                    Math.cos(lat1) * Math.sin(lat2) - Math.sin(lat1) * Math.cos(lat2) * Math.cos(lon2-lon1)),
                pi * 2);
        angle = fmod(((angle * (180 / pi)) + 360), 360);

        var a = Math.sin(dt/2) * Math.sin(dt/2) + Math.cos(t1) * Math.cos(t2) * Math.sin(ds/2) * Math.sin(ds/2);
        var c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
        var distance = R * c;

        return [distance, angle];
    }

    //
    // This function is called whenever selectedMark is changed
    //
    function newMarkSelected()
    {
        refreshCount = 1;
        if (selectedFolder != -1 && selectedMark != -1)
        {
            desiredPosition[0] = marks[selectedFolder][selectedMark]["y"];
            desiredPosition[1] = marks[selectedFolder][selectedMark]["x"];
            /* DEADCODE
            if (desiredPosition[0] instanceof Toybox.Lang.String) { desiredPosition[0] = convertDegreesMinutes(desiredPosition[0]); }
            if (desiredPosition[1] instanceof Toybox.Lang.String) { desiredPosition[1] = convertDegreesMinutes(desiredPosition[1]); }
            */
            markName = marks[selectedFolder][selectedMark]["n"];
            var colon = markName.find(":");
            markShortname = "";
            if (colon != null)
            {
                markShortname = markName.substring(0, colon);
                markName = markName.substring(colon + 1, markName.length());
            }
            var app = App.getApp();
            app.setProperty("selectedMark", selectedMark);
            app.setProperty("selectedFolder", selectedFolder);
            Ui.requestUpdate();
        }
        else
        {
            markName = [ "none" ];
            markShortname = "Press Menu to select a mark";
            desiredPosition[0] = -1;
            desiredPosition[1] = -1;
        }
    }

    //
    // called when the menu key is hit.  Our menu lists all of the wind
    // stations and lets a user pick one.
    //
    function onMenu() {
        resetMenu();
        recoverFromReduceMemory();
        var maxMenuItems = maxMenuItems();


        if (menuLevel == 0)
        {
            for (var i = 0; i < marks.size(); i++)
            {
                System.println("marks[i].size = " + marks[i].size());
                System.println("maxMenuItems = " + maxMenuItems);
                if (marks[i].size() > maxMenuItems)
                {
                    if (loadError == null) 
                    {
                        loadError = "Folder has over 40 items: " + folderNames[i];
                        loadErrorCode = null;
                    }
                }
            }

            // pick a folder out of the list.  
            menu.setTitle("Folders:");
            for (var i = 0; i < marks.size(); i++) 
            {
                addMenuItem(folderNames[i]);
            } 
            addMenuItem("<Load Marks>");
            var app = App.getApp();
            var calTopoId = app.getProperty("calTopoId");
            addMenuItem("Caltopo ID: " + calTopoId);
            if (loadError != null) 
            {
                addMenuItem("er: " + loadError);
            }
            if (loadErrorCode != null) 
            {
                addMenuItem("code: " + loadErrorCode);
            }
        }
        else if (menuLevel == 1)
        {
            // pick a mark out of this folder
            menu.setTitle(folderNames[selectedFolder] + " Marks:");
            addMenuItem("<change folder>");
            for (var i = 0; i < folderMarks.size(); i++) 
            {
                addMenuItem(folderMarks[i]["n"]);
            } 
        }
        showMenu();
        return true;
    }

    //
    // called when a menu item is selected
    // 
    // index -- the menu item selected
    //
    function menuItemSelected(index) {
        if (menuLevel == 0)
        {
            if (index >= marks.size())
            {
                if (index == marks.size() + 1)
                {
                    reduceMemory();
                }
                else
                {
                    reloadFromWeb = true;
                    requestMarkDataFromCaltopo();        
                }
            }
            else
            {
                menuLevel = 1;
                selectedFolder = index;
                folderMarks = marks[selectedFolder];
                Ui.popView(Ui.SLIDE_DOWN);
                onMenu();
            }
        }
        else 
        {
            if (index == 0)
            {
                menuLevel = 0;
                Ui.popView(Ui.SLIDE_DOWN);
                onMenu();
            }
            else 
            {
                selectedMark = index - 1;
                newMarkSelected();
            }
        }
    }

    //
    // cycle through the wind stations by swiping
    //
    function onSwipeUp() {
        //reduceMemory();
        recoverFromReduceMemory();
        if (folderMarks != null)
        {
            if ((folderMarks != null) && (folderMarks.size() > 0)) {
                selectedMark = (selectedMark + 1) % folderMarks.size();
                newMarkSelected();
            }
        }
    }

    //
    // used to cycle through wind stations
    //
    function onSwipeDown() {
        //reduceMemory();
        recoverFromReduceMemory();
        if (folderMarks != null)
        {
            if ((folderMarks != null) && (folderMarks.size() > 0)) {
                selectedMark--;
                if (selectedMark < 0) { selectedMark = folderMarks.size() - 1; }
                newMarkSelected();
            }
        }
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

        // word wrap the mark name if we only have a string
        if (markName instanceof Toybox.Lang.String)
        {
            markName = CommonView.wordWrap(dc, Graphics.FONT_XTINY, markName);
        }

        if (!reloadFromWeb && (folderMarks != null) && (folderMarks.size() > 0)) 
        {
            //
            // normal view with a mark selected
            //
            dc.drawLine(0, y-1, screenWidth, y-1);
            // what we'll show
            var distance = "no GPS";
            var angle = "---";
            var vmg = "---";
            var relativeAngle = "---";
            //var fieldFonts = [ Graphics.FONT_NUMBER_MEDIUM, Graphics.FONT_NUMBER_MILD, Graphics.FONT_NUMBER_MILD ];
            var fieldFonts = [ Graphics.FONT_NUMBER_MEDIUM ];
            var cogText = (cog * 57.2957795);
            if (cogText < 0) { cogText += 360; }
            cogText = cogText.toNumber();

            if (position != null)
            {
                var a = measureDistance(position, desiredPosition);
                distance = a[0].format("%.1f");
                angle = a[1].toNumber();
                vmg = self.speed * 1.94384449 * Math.cos(self.cog - (angle / 57.2957795));
                vmg = vmg.format("%02.1f");
            } 
            else 
            {
                fieldFonts = [ Graphics.FONT_LARGE ];
            }

            // station ID on top
            dc.drawText(center, y, Graphics.FONT_MEDIUM, folderNames[selectedFolder] + "/" + markShortname, Graphics.TEXT_JUSTIFY_CENTER);
            y += dc.getFontHeight(Graphics.FONT_MEDIUM) - 5;
            var markNameIndex = (refreshCount / 20) % markName.size();
            dc.drawText(center, y, Graphics.FONT_XTINY, markName[markNameIndex], Graphics.TEXT_JUSTIFY_CENTER);
            refreshCount++;
            y += dc.getFontHeight(Graphics.FONT_XTINY);

            self.drawHalfWidthFields(dc, 0, y, [ distance ], [ "dtw" ], fieldFonts);
            y = self.drawHalfWidthFields(dc, quarterWidth * 2, y, [ vmg ], [ "vmg" ], fieldFonts);
            self.drawHalfWidthFields(dc, 0, y, [ angle ], [ "btw" ], fieldFonts);
            /*
            System.println(angle);
            System.println(cogText);
            if (angle != "---")
            {
                relativeAngle = cogText - angle;
            }
            self.drawHalfWidthFields(dc, 0, y, [ relativeAngle ], [ "ang" ], fieldFonts);
            */
            self.drawHalfWidthFields(dc, quarterWidth * 2, y, [ cogText ], [ "cog" ], fieldFonts);
        } 
        else if (reloadFromWeb && loadError == null)
        {
            //
            // shown when loading marks from the internet
            //
            var y = 20;
            var font = Graphics.FONT_MEDIUM;
            y += dc.getFontHeight(font) + 4;
            dc.drawText(dc.getWidth() / 2, y, font, "Loading Marks...", Graphics.TEXT_JUSTIFY_CENTER);    
        } 
        else if (loadError != null)
        {
            //
            // shown we had trouble loading marks
            //
            var y = 20;
            var font = Graphics.FONT_MEDIUM;
            var strings = new [2];
            strings[0] = "Error while loading marks:";
            strings[1] = loadError;

            var i;
            var j;
            for (i = 0; i < strings.size(); i++)
            {
                var substrings = wordWrap(dc, font, strings[i]);
                for (j = 0; j < substrings.size(); j++) 
                {
                    dc.drawText(dc.getWidth() / 2, y, font, substrings[j], Graphics.TEXT_JUSTIFY_CENTER);
                    y += dc.getFontHeight(font) + 4;
                }
            }
        }
        else 
        {
            //
            // shown when no mark is selected.  Prompt the user to get started.
            //
            var y = 20;
            var font = Graphics.FONT_MEDIUM;
            y += dc.getFontHeight(font) + 4;
            dc.drawText(dc.getWidth() / 2, y, font, "No mark selected", Graphics.TEXT_JUSTIFY_CENTER);    
            y += dc.getFontHeight(font) + 4;
            dc.drawText(dc.getWidth() / 2, y, font, "Press Menu", Graphics.TEXT_JUSTIFY_CENTER);    
        }

        // draw a G in the upper left showing GPS status
        dc.setColor(GpsAccuracyColor($.gpsAccuracy), Graphics.COLOR_TRANSPARENT);
        dc.drawText(0, 0, Graphics.FONT_XTINY, "G", Graphics.TEXT_JUSTIFY_LEFT);

        CommonView.onUpdate(dc);
    }
}
