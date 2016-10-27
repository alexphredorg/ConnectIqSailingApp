using Toybox.WatchUi as Ui;

class SailingAppDelegate extends Ui.BehaviorDelegate {
    var viewIndex = 0;
    var currentView = null;
    var views;

    function initialize() {
        // initialize the list of views here.  currently all views
        // need to be running at all times, in the future we may
        // support views that only get initialized when they are in the
        // foreground
        var timerView = new TimerView();
        var tidesView = new TidesView();
        var windsView = new WindsView();
        views = [ timerView, tidesView, windsView ];
        BehaviorDelegate.initialize();
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
            var dialog = new Ui.Confirmation("Really quit?");
            Ui.pushView(dialog, new ConfirmQuitDelegate(), Ui.SLIDE_IMMEDIATE);
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