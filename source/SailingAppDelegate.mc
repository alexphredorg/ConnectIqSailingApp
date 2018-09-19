using Toybox.WatchUi as Ui;
using Toybox.Time as Time;
using Toybox.Application as App;
using Toybox.Attention;
using Toybox.Timer;

//
// Generic input delegate that should work on more watches.  Tested on the HR
//
class SailingAppDelegateGeneric extends Ui.BehaviorDelegate {
    var viewIndex = 0;
    var currentView = null;
    var views;
    var checkedLocation = false;

    function initialize() {
        var viewsDict = {};
        var viewCount = 0;

        // read our settings
        var app = App.getApp();
        var detectedPugetSound = app.getProperty("detectedPugetSound");
        var forcePugetSound = app.getProperty("forcePugetSound");
        var hideTimerView = app.getProperty("hideTimerView");
        var hideMarksView = app.getProperty("hideMarksView");
        var hideTidesView = app.getProperty("hideTidesView");
        var hideWindsView = app.getProperty("hideWindsView");

        if (detectedPugetSound == null) { detectedPugetSound = false; }
        if (forcePugetSound == null) { forcePugetSound = false; }
        if (hideTimerView == null) { hideTimerView = false; }
        if (hideMarksView == null) { hideMarksView = false; }
        if (hideTidesView == null) { hideTidesView = false; }
        if (hideWindsView == null) { hideWindsView = false; }

        // initialize all views.  At the end of this we have a dict
        // sorted with the views that we want, plus a size of the dict
        if (!hideTimerView)
        {
            System.println("Timer view: enabled");
            viewsDict[viewCount] = new TimerView();
            viewCount++;
        }

        if (!hideMarksView)
        {
            System.println("Marks view: enabled");
            viewsDict[viewCount] = new MarksView();
            viewCount++;
        }

        if (!hideTidesView)
        {
            System.println("Tides view: enabled");
            viewsDict[viewCount] = new TidesView();
            viewCount++;
        }

        if ((detectedPugetSound || forcePugetSound) && !hideWindsView)
        {
            System.println("Winds view: enabled");
            viewsDict[viewCount] = new TidesView();
            viewCount++;
        }
        
        // transfer from the dict to an array
        views = new [viewCount];
        for (var i = 0; i < viewCount; i++)
        {
            views[i] = viewsDict[i];
        }
        viewsDict = null;

        // turn on the GPS
        System.println("enable GPS");
        Position.enableLocationEvents(Position.LOCATION_CONTINUOUS, method(:onPositionUpdate));

        // call parent
        BehaviorDelegate.initialize();
    }

    function reduceMemory()
    {
        for (var i = 0; i < views.size(); i++)
        {
            views[i].reduceMemory();
        }
    }

    // Called whenever we get a new position from the GPS
    function onPositionUpdate(info)
    {
        // these views depend on position.
        // HACK -- let them register or otherwise have us detect it
        views[0].onPositionUpdate(info);
        views[1].onPositionUpdate(info);
        views[2].onPositionUpdate(info);

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

            if (inPugetSound && views.size() == 2)
            {
                System.println("Adding Puget Sound views");
                var windsView = new WindsView();
                views = [ views[0], views[1], views[2], windsView ];
            }
        }
    }

    // forward menu clicks to the current view
    function onMenu() {
        return currentView.onMenu();
    }
    
    // forward screen taps to the current view
    function onTap(evt) {
        return currentView.screenTap(evt);
    }

    // forward button presses to the current view
    function onKey(evt) {
        var key = evt.getKey();
        if (key == KEY_ESC) {
            currentView.onEscKey();
        } else if (key == KEY_ENTER) { 
            currentView.onEnterKey();
        }
        return true;
    }

    // forward swipe events to the current view
    function onSwipe(evt) {
        var swipe = evt.getDirection();

        if (swipe == SWIPE_UP) {
            currentView.onSwipeUp();
            return true;
        } else if (swipe == SWIPE_DOWN) {
            currentView.onSwipeDown();
            return true;
        }
        return false;
    }

    // change to the new view
    function onNextPage() {
        viewIndex = (viewIndex + 1) % views.size();
        Ui.switchToView(getCurrentView(), self, Ui.SLIDE_LEFT);
    }

    // change to the previous view
    function onPreviousPage() {
        viewIndex = viewIndex - 1;
        if (viewIndex < 0) { viewIndex = views.size() - 1; }
        Ui.switchToView(getCurrentView(), self, Ui.SLIDE_RIGHT);
    }

    // get the current view as defined by viewIndex.  This
    // also updates the currentView pointer
    function getCurrentView() {
        var view = views[viewIndex];
        currentView = view;
        return view;
    }
}

//
// Custom input delegate for the Vivoactive_HR.  This version is biased towards hard
// keys to make it easier to use on a sailboat.
//
// Works on the simulator, but onKeyRelease doesn't work on the watch which makes this whole
// model broken.
//
class SailingAppDelegateVAHR extends Ui.BehaviorDelegate {
    var viewIndex = 0;
    var currentView = null;
    var views;
    var marksView;

    function initialize() {
        // read our settings
        var app = App.getApp();
        var autoDetectPugetSound = app.getProperty("autoDetectPugetSound");
        var detectedPugetSound = app.getProperty("detectedPugetSound");
        var forcePugetSound = app.getProperty("forcePugetSound");

        // initialize the list of views here.  currently all views
        // need to be running at all times, in the future we may
        // support views that only get initialized when they are in the
        // foreground
        var timerView = new TimerView();
        var marksView = new MarksView();
        $.marksView = marksView;
        if ((autoDetectPugetSound && detectedPugetSound) || forcePugetSound)
        {
            var tidesView = new TidesView();
            var windsView = new WindsView();
            views = [ timerView, marksView, tidesView, windsView ];
        }
        else 
        {
            views = [ timerView, marksView ];
        }
        BehaviorDelegate.initialize();
    }


    const KEY_STATE_SHORT_PRESS = 0;
    const KEY_STATE_MID_PRESS = 1;
    const KEY_STATE_LONG_PRESS = 2;

    var inputTimer = null;
    var inputKey = 0;
    var keyState = KEY_STATE_SHORT_PRESS;

    //
    // onKeyPressed is called by the OS when a button is pressed.  The VAHR only has two buttons,
    // ESC is the left one and ENTER is the right one.  We keep independent timers for each button
    // to track how long they've been pressed for upon release.
    //
    function onKeyPressed(evt)
    {
        System.println("onKeyPressed");
        inputKey = evt.getKey();
        keyState = KEY_STATE_SHORT_PRESS;
        if (inputTimer == null)
        {
            inputTimer = new Timer.Timer();
            inputTimer.start(method(:longPress), 1000, false);
        }
        else
        {
            System.println("second keypress as first is held");
        }
        return true;
    }

    //
    // longPress is called by our timer when a user keeps holding a key without letting go.  We 
    // support two versions of a long press, 1 second and 3 seconds.
    //
    function longPress()
    {
        keyState++;
        if (keyState == KEY_STATE_MID_PRESS)
        {
            var vibrateData = [ new Attention.VibeProfile(100, 50) ];
            Attention.vibrate(vibrateData);
            inputTimer.stop();
            inputTimer.start(method(:longPress), 2000, false);
        }
        else if (keyState == KEY_STATE_LONG_PRESS)
        {
            inputTimer.stop();
            inputTimer = null;
            self.handleKeyPress();
        }
    }

    // 
    // onKeyRelease is called when a button is released.  This gets mapped into an action on the view.
    //
    function onKeyReleased(evt)
    {
        System.println("onKeyReleased");
        var now = System.getTimer();
        var start = null;
        var key = evt.getKey();
        if (key == inputKey)
        {
            if (keyState == KEY_STATE_LONG_PRESS)
            {
                // this was caught in longPress, we're done
            } 
            else 
            {
                inputTimer.stop();
                inputTimer = null;
                self.handleKeyPress();
            }
        } 
        else 
        {
            System.println("release doesn't match pressed key, ignoring");
        }
        return true;
    }

    //
    // helper function that maps our 6 forms of key presses into the appropriate handler
    //
    function handleKeyPress()
    {
        if (self.inputKey == KEY_ESC)
        {
            if (self.keyState == KEY_STATE_SHORT_PRESS) 
            {
                self.currentView.onEscKey();
            }
            else if (self.keyState == KEY_STATE_MID_PRESS) 
            {
                self.previousPage();
            }
            else if (self.keyState == KEY_STATE_LONG_PRESS)
            {
                self.onQuit();
            }
        } else if (self.inputKey == KEY_ENTER)
        {
            if (self.keyState == KEY_STATE_SHORT_PRESS) 
            {
                self.currentView.onEnterKey();
            }
            else if (self.keyState == KEY_STATE_MID_PRESS) 
            {
                self.nextPage();
            }
            else if (self.keyState == KEY_STATE_LONG_PRESS)
            {
                self.currentView.onMenu();
            }
        }
    }

    //
    // We do this at a lower level using onKeyPressed and onKeyReleased.  Override onKey
    //
    function onKey(evt) {
        return true;
    }

    //
    // onQuit is called when the user quits the app.  This is done with a long press of ESC.
    //
    function onQuit() {
        var dialog = new Ui.Confirmation("Really quit?");
        Ui.pushView(dialog, new ConfirmQuitDelegate(), Ui.SLIDE_IMMEDIATE);
    }

    //
    // forward menu clicks to the current view
    //
    function onMenu() {
        return false;
        // return currentView.onMenu();
    }
    
    //
    // forward screen taps to the current view
    //
    function onTap(evt) {
        return currentView.screenTap(evt);
    }

    //
    // forward swipe events to the current view
    //
    function onSwipe(evt) {
        var swipe = evt.getDirection();

        if (swipe == SWIPE_UP) 
        {
            currentView.onSwipeUp();
            return true;
        } 
        else if (swipe == SWIPE_DOWN) {
            currentView.onSwipeDown();
            return true;
        }
        else if (swipe == SWIPE_LEFT)
        {
            nextPage();
        } 
        else if (swipe == SWIPE_RIGHT)
        {
            previousPage();
        }
        return false;
    }

    function previousPage()
    {
        viewIndex = viewIndex - 1;
        if (viewIndex < 0) { viewIndex = views.size() - 1; }
        Ui.switchToView(getCurrentView(), self, Ui.SLIDE_RIGHT);
    }

    function nextPage()
    {
        viewIndex = (viewIndex + 1) % views.size();
        Ui.switchToView(getCurrentView(), self, Ui.SLIDE_LEFT);
    }

    //
    // get the current view as defined by viewIndex.  This
    // also updates the currentView pointer
    //
    function getCurrentView() {
        var view = views[viewIndex];
        currentView = view;
        return view;
    }
}

class ConfirmQuitDelegate extends Ui.ConfirmationDelegate {
    function initialize() {
        return Ui.ConfirmationDelegate.initialize();
    }
    function onResponse(value) {
        if (value == 0) {
            return;
        }
        else {
            System.exit();
        }
    }
}
