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
// MarksView shows information about course marks loaded from CalTopo
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
    var reloadFromWeb = false;
    var refreshCount = 1;
    var shrunk = false;
    var loadError = null;
    var loadErrorCode = null;
    var errorMode = false;
    var errorText1 = "";
    var errorText2 = "";
    var viewErrorMode = null;

    //
    // initialize the view
    //
    function initialize() {
        highSpeedRefresh = true;
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
        System.println("in defaultMarks()");
        folderNames = [];
        marks = [];
        selectedMark = -1;
        selectedFolder = -1;
        folderMarks = null;
        setMode(true, "No Mark Selected", "Press Menu to start");
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
            setMode(true, "Invalid CalTopoID", "rc=" + responseCode);
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
        //System.println("point1 = " + point1[0] + "," + point1[1]);
        //System.println("point2 = " + point2[0] + "," + point2[1]);

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
    // insert the list of folders into the menu
    //
    function addViewMenuItems(menu)
    {
        System.println("adding view menu items for marks");
        for (var i = 0; i < marks.size(); i++)
        {
            menu.addItem(new Ui.MenuItem(folderNames[i], "Folder " + folderNames[i], :folder, {}));
        }

        menu.addItem(new Ui.MenuItem("Load", "Load Marks from CalTopo", :loadMarks, {}));
    }

    // 
    // handle folder menu items
    //
    function viewMenuItemSelected(symbol, item)
    {
        if (symbol == :folder)
        {
            var index = -1;
            for (var i = 0; i < marks.size(); i++)
            {
                System.println(item.getLabel() + " compare " + folderNames[i]);
                if (folderNames[i] == item.getLabel())
                {
                    index = i;
                }
            }
            if (index >= 0)
            {
                selectedFolder = index;
                folderMarks = marks[selectedFolder];
                if (folderMarks.size() > 0)
                {
                    selectedMark = 0;
                    newMarkSelected();
                }
                else
                {
                    defaultMarks();
                }
                Ui.popView(Ui.SLIDE_DOWN);
                return true;
            }
        }
        else if (symbol == :loadMarks)
        {
            reloadFromWeb = true;
            requestMarkDataFromCaltopo();        
            Ui.popView(Ui.SLIDE_DOWN);
        }
        return false;
    }

    //
    // cycle through the wind stations by swiping
    //
    function onUpKey() {
        recoverFromReduceMemory();
        if (folderMarks != null)
        {
            if ((folderMarks != null) && (folderMarks.size() > 0)) {
                selectedMark = (selectedMark + 1) % folderMarks.size();
                newMarkSelected();
            }
        }
        return true;
    }

    //
    // used to cycle through wind stations
    //
    function onDownKey() {
        recoverFromReduceMemory();
        if (folderMarks != null)
        {
            if ((folderMarks != null) && (folderMarks.size() > 0)) {
                selectedMark--;
                if (selectedMark < 0) { selectedMark = folderMarks.size() - 1; }
                newMarkSelected();
            }
        }
        return true;
    }

    // Load your resources here
    function onLayout(dc) {
        System.println("onLayout: viewErrorMode=" + viewErrorMode);
        System.println("onLayout: errorMode=" + errorMode);
        if (viewErrorMode != errorMode)
        {
            if (errorMode)
            {
                setLayout(Rez.Layouts.MarksViewError(dc));
            }
            else
            {
                setLayout(Rez.Layouts.MarksView(dc));
            }
            viewErrorMode = errorMode;
        }
        
        CommonView.onLayout(dc);
    }

    function setMode(errorMode, errorText1, errorText2)
    {
        self.errorText1 = errorText1;
        self.errorText2 = errorText2;
        self.errorMode = errorMode;
    }

    //
    // this is an ugly mess and should be cleaned up, but it works
    // for now
    //
    function setModeFromFlags()
    {
        if (!reloadFromWeb && (folderMarks != null) && (folderMarks.size() > 0))
        {
            setMode(false, "", "");
        } 
        else if (reloadFromWeb)
        {
            setMode(true, "Loading Marks", "");
        }
        else if (self.position == null)
        {
            setMode(true, "No GPS Signal", "");
        }
        else if (folderMarks == null)
        {
            // setMode was called on the load failure, and set the string
        }
    }

    //
    // Update the view
    //
    function onUpdate(dc) {
        setModeFromFlags();

        if (viewErrorMode != errorMode)
        {
            onLayout(dc);
        }

        // word wrap the mark name if we only have a string
        if (markName instanceof Toybox.Lang.String)
        {
            markName = CommonView.wordWrap(dc, Graphics.FONT_XTINY, markName);
        }
        var markNameIndex = (refreshCount / 20) % markName.size();
        refreshCount++;

        var markIdText = "---";
        var markNameText = "(no mark)";
        var relativeAngle = -1;

        if (selectedFolder >= 0 && markNameIndex >= 0)
        {
            markIdText = folderNames[selectedFolder] + "/" + markShortname;
            markNameText = markName[markNameIndex];
        }

        CommonView.setValueText("MarkId", markIdText);
        CommonView.setValueText("MarkName", markNameText);

        if (errorMode)
        {
            CommonView.setValueText("ErrorLabel1", errorText1);
            CommonView.setValueText("ErrorLabel2", errorText2);
        }
        else
        {
            //
            // normal view with a mark selected, this uses the layout
            //

            var distance = "---";
            var angle = "---";
            var vmg = "---";
            
            if (position != null)
            {
                var a = measureDistance(position, desiredPosition);
                if (a[0] > 1000)
                {
                    distance = a[0].format("%0.0f");
                }
                else 
                {
                    distance = a[0].format("%0.1f");
                }
                angle = a[1].toNumber();
                var cog = ($.heading * 57.2957795).toNumber();
                // compute a relative angle from -180 to 180 degrees from our cog to the mark
                relativeAngle = (((((cog + 360) % 360) - ((angle + 360) % 360)) + 360) % 360) - 180;
                //System.println("cog = " + cog + " : angle = " + angle + " : relativeAngle = " + relativeAngle);
                vmg = self.speed * 1.94384449 * Math.cos(self.cog - (angle / 57.2957795));
                vmg = vmg.format("%02.1f");
                angle = a[1].format("%0.0f");

                // switch relative angle to the watch's stupid coordinates: 
                // 0 degrees: 3 o'clock position.
                // 90 degrees: 12 o'clock position.
                // 180 degrees: 9 o'clock position.
                // 270 degrees: 6 o'clock position.
                relativeAngle = relativeAngle + 270;
            } 

            CommonView.setValueText("BtwValue", angle);
            CommonView.setValueText("VmgValue", vmg);
            CommonView.setValueText("DtwValue", distance);
        }

        CommonView.onUpdate(dc);
        if (relativeAngle >= 0)
        {
            dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
            var width = 1;
            var maxRadius = screenWidth / 2;
            var minRadius = maxRadius - 10;
            for (var radius = minRadius; radius < maxRadius; radius++)
            {
                dc.drawArc(self.screenWidth / 2, self.screenHeight / 2, radius, Graphics.ARC_CLOCKWISE, relativeAngle + width, relativeAngle - width);
            }
        }
    }
}
