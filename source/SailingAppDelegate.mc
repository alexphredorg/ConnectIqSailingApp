using Toybox.WatchUi as Ui;
using Toybox.Time as Time;
using Toybox.Application as App;
using Toybox.Attention;
using Toybox.Timer;

class MyMenu2Delegate extends Ui.Menu2InputDelegate {
    var view;

    function initialize(viewPointer) {
        view = viewPointer;
        Menu2InputDelegate.initialize();
    }

    function onSelect(item) {
        System.println(item.getId());
        view.menuItemSelected(item);
    }
}

//
// Generic input delegate that should work on more watches.  Tested on the HR
//
class SailingAppDelegateGeneric extends Ui.BehaviorDelegate {
    var viewIndex = 0;
    var currentView = null;
    var viewsDict = {};
    var viewsTempDict = {};
    var views;
    var checkedLocation = false;
    var oneButtonMode = false;

    function initialize() {
        // this helps to detect VA3 which is a weird watch with only one
        // physical button
        var settings = System.getDeviceSettings();
        if (settings.inputButtons == 1 && settings.isTouchScreen)
        {
            oneButtonMode = true;
        }

        // read our settings
        var app = App.getApp();
        var detectedPugetSound = app.getProperty("detectedPugetSound");
        var forcePugetSound = app.getProperty("forcePugetSound");
        var hideTimerView = app.getProperty("hideTimerView");
        var hideMarksView = app.getProperty("hideMarksView");
        var hideTidesView = app.getProperty("hideTidesView");
        var hideWindsView = app.getProperty("hideWindsView");
        var viewCount = 0;

        if (detectedPugetSound == null) { detectedPugetSound = false; }
        if (forcePugetSound == null) { forcePugetSound = false; }
        if (hideTimerView == null) { hideTimerView = false; }
        if (hideMarksView == null) { hideMarksView = false; }
        if (hideTidesView == null) { hideTidesView = false; }
        if (hideWindsView == null) { hideWindsView = true; }

        // initialize all views.  At the end of this we have a dict
        // sorted with the views that we want, plus a size of the dict
        if (!hideTimerView)
        {
            System.println("Timer view: enabled");
            viewsDict[:timerView] = new TimerView();
            viewsTempDict[viewCount] = viewsDict[:timerView];
            viewCount++;
        }
        else
        {
            viewsDict[:timerView] = null;
        }

        if (!hideMarksView)
        {
            System.println("Marks view: enabled");
            viewsDict[:marksView] = new MarksView();
            viewsTempDict[viewCount] = viewsDict[:marksView];
            viewCount++;
        }
        else
        {
            viewsDict[:marksView] = null;
        }

        if (!hideTidesView)
        {
            System.println("Tides view: enabled");
            viewsDict[:tidesView] = new TidesView();
            viewsTempDict[viewCount] = viewsDict[:tidesView];
            viewCount++;
        }
        else
        {
            viewsDict[:tidesView] = null;
        }

        if ((detectedPugetSound || forcePugetSound) && !hideWindsView)
        {
            System.println("Winds view: enabled");
            viewsDict[:windsView] = new WindsView();
            viewsTempDict[viewCount] = viewsDict[:windsView];
            viewCount++;
        }
        else
        {
            viewsDict[:windsView] = null;
        }
        
        // transfer from the dict to an array
        views = new [viewCount];
        System.println("viewCount = " + viewCount);
        for (var i = 0; i < viewCount; i++)
        {
            views[i] = viewsTempDict[i];
            System.println("views[i] = " + views[i]);
        }
        viewsTempDict = {};

        // turn on the GPS
        System.println("enable GPS");
        Position.enableLocationEvents(Position.LOCATION_CONTINUOUS, method(:onPositionUpdate));

        // set the default view
        currentView = viewsDict[:timerView];

        // call parent
        BehaviorDelegate.initialize();
    }

    function reduceMemory()
    {
        for (var i = 0; i < views.size(); i++)
        {
            if (views[i] != null)
            {
                views[i].reduceMemory();
            }
        }
    }

    // Called whenever we get a new position from the GPS
    function onPositionUpdate(info)
    {
        // send position updates to all views
        for (var i = 0; i < views.size(); i++)
        {
            if (views[i] != null) 
            {
                views[i].onPositionUpdate(info);
            }
        }

        // check our location to see if we're in Puget Sound to enable more screens
        if (!checkedLocation && info.position != null)
        {
            var pos = info.position.toDegrees();
            var app = App.getApp();
            var inPugetSound = false;
            if (pos[0] > 46.75 && pos[0] < 49 && pos[1] > -125 && pos[1] < -121) { inPugetSound = true; }
            app.setProperty("detectedPugetSound", inPugetSound);
            System.println("inPugetSound = " + inPugetSound);
            checkedLocation = true;

            /* hate this hack, removing for now, users can restart to see wind 
            if (inPugetSound && views.size() == 2)
            {
                System.println("Adding Puget Sound views");
                var windsView = new WindsView();
                views = [ views[0], views[1], views[2], windsView ];
            }
            */
        }
    }

    // forward menu clicks to the current view
    function onMenu() 
    {
        return currentView.onMenu();
    }
    
    // forward screen taps to the current view
    function onTap(evt) 
    {
        return currentView.screenTap(evt);
    }

    // start/stop, enter, or screen touch
    function onSelect()
    {
        return currentView.onEnterKey();
    }

    // esc or back button
    function onBack()
    {
        return currentView.onEscKey();
    }

    // down button
    function onNextPage() 
    {
        return currentView.onDownKey();
    }

    // up button
    function onPreviousPage() 
    {
        return currentView.onUpKey();
    }

    function getCurrentView() 
    {
        return currentView;
    }

    // menu items for switching between views
    function addViewMenuItems(menu)
    {
        if (viewsDict[:timerView] != null && currentView != viewsDict[:timerView])
        {
            menu.addItem(new Ui.MenuItem("Timer", "Show Timer Page", :timerView, {}));
        }
        if (viewsDict[:marksView] != null && currentView != viewsDict[:marksView])
        {
            menu.addItem(new Ui.MenuItem("Marks", "Show Marks Page", :marksView, {}));
        }
        if (viewsDict[:tidesView] != null && currentView != viewsDict[:tidesView])
        {
            menu.addItem(new Ui.MenuItem("Tides", "Show Tides Page", :tidesView, {}));
        }
        if (viewsDict[:windsView] != null && currentView != viewsDict[:windsView])
        {
            menu.addItem(new Ui.MenuItem("Winds", "Show Winds Page", :windsView, {}));
        }
    }

    // handle view changes
    function viewMenuItemSelected(menuItemSymbol, item)
    {
        var viewSymbol = menuItemSymbol;
        if (viewsDict[menuItemSymbol] != null)
        {
            currentView = viewsDict[menuItemSymbol];
            Ui.popView(Ui.SLIDE_DOWN);
            Ui.switchToView(viewsDict[menuItemSymbol], self, Ui.SLIDE_IMMEDIATE);
            return true;
        }
        else
        {
            return false;
        }
    }
}

var quitAfterSave = false;
class ConfirmQuitDelegate extends Ui.ConfirmationDelegate 
{
    var timer = null;

    function initialize() 
    {
        return Ui.ConfirmationDelegate.initialize();
    }
    function onResponse(value) 
    {
        System.println("ConfirmQuitDelegate.onResponse");
        System.println("value = " + value);
        if (value == 0) 
        {
            return;
        }
        else 
        {
            if ($.session != null)
            {
                $.quitAfterSave = true;
                timer = new Timer.Timer();
                // prompt for save when this dialog exits
                timer.start(method(:promptSave), 1, false);
            }
            else
            {
                System.exit();
            }
        }
    }

    function promptSave()
    {
        timer.stop();
        timer = null;
        var dialog = new Ui.Confirmation("Save track?");
        Ui.pushView(dialog, new ConfirmSaveDelegate(), Ui.SLIDE_IMMEDIATE);
    }
}

class ConfirmResetDelegate extends Ui.ConfirmationDelegate 
{
    var timer = null;

    function initialize() 
    {
        return Ui.ConfirmationDelegate.initialize();
    }
    function onResponse(value) 
    {
        System.println("ConfirmResetDelegate.onResponse");
        System.println("value = " + value);
        if (value != 0) 
        {
            if ($.session)
            {
                timer = new Timer.Timer();
                // prompt for save when this dialog exits
                timer.start(method(:promptSave), 1, false);
            }
            else
            {
                $.timer.reset();
            }
        }
    }

    function promptSave()
    {
        timer.stop();
        timer = null;
        var dialog = new Ui.Confirmation("Save track?");
        Ui.pushView(dialog, new ConfirmSaveDelegate(), Ui.SLIDE_IMMEDIATE);
    }
}

class ConfirmSaveDelegate extends Ui.ConfirmationDelegate 
{
    function initialize() 
    {
        return Ui.ConfirmationDelegate.initialize();
    }
    function onResponse(value) 
    {
        System.println("ConfirmSaveDelegate.onResponse");
        System.println("value = " + value);
        $.session.stop();
        if (value != 0) 
        {
            $.session.save();
            System.println("saving session");
        }
        $.session = null;
        $.timer.reset();
        if ($.quitAfterSave)
        {
            System.exit();
        }
    }
}
