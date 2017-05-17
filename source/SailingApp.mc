using Toybox.Application as App;
using Toybox.WatchUi as Ui;

function onPosition(info)
{
    System.println("locationListener");
    speed = info.speed;
}

class Sailing extends App.AppBase {
    var inputDelegate = null;

    function initialize() {
        AppBase.initialize();
    }

    // onStart() is called on application start up
    function onStart(state) {
    }

    // onStop() is called when your application is exiting
    function onStop(state) {
    }

    // Return the initial view of your application here
    function getInitialView() {
        inputDelegate = new SailingAppDelegateGeneric();
        return [ inputDelegate.getCurrentView(), inputDelegate ];
    }

    // call all views asking them to shrink
    function reduceMemory() {
        inputDelegate.reduceMemory();
    }
}
