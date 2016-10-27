using Toybox.Communications as Comm;

var queuedComm = new QueuedComm();

// looks and acts like Toybox.Communications, but it has a much deeper queue
class QueuedComm {
    const SLOTS = 4;

    var slotFunction = null;
    var slot = [ null, null, null, null ];
    // circular buffer of pending requests
    var pending = new [100];
    var pendingHead = 0;
    var pendingTail = 0;
    var slotsInUse = 0;

    // just like Comm.makeWebRequest
    // returns false when the queue is full
    function makeWebRequest(url, params, options, responseMethod, responseVar)
    {

        System.println("QueuedComm: pending a new makeWebRequest");
        // save away the params
        var dict = { 
            :url=>url, 
            :params=>params, 
            :options=>options, 
            :responseMethod=>responseMethod, 
            :responseVar=>responseVar };

        // add to the pending queue, with a simple overflow check
        var oldPendingHead = pendingHead;
        pendingHead = (pendingHead + 1) % pending.size();
        if (pendingHead == pendingTail) {
            pendingHead = oldPendingHead;
            return false;
        }

        // save our data in the pending queue
        pending[oldPendingHead] = dict;

        System.println("pendingHead = " + pendingHead);

        if (slotsInUse < SLOTS) {
            return makeNextWebRequest();
        }

        return true;
    }

    function makeNextWebRequest() {
        // nothing to do
        if (pendingTail == pendingHead) { return false; }

        if (slotFunction == null) {
            slotFunction = [ method(:response0), method(:response1), method(:response2), method(:response3) ];
        }
        System.println("QueuedComm: doing a real makeWebRequest");

        var dict = pending[pendingTail];
        pendingTail = (pendingTail + 1) % pending.size();

        System.println(slotFunction[0]);
        for (var i = 0; i < SLOTS; i++) {
            if (slot[i] == null) { 
                slot[i] = [ dict[:responseMethod], dict[:responseVar] ];
                Comm.makeWebRequest(dict[:url], dict[:params], dict[:options], slotFunction[i]);
                slotsInUse++;
                System.println("QueuedComm: used slot " + i + ", slotsInUse=" + slotsInUse);
                return true;
            }
        }
        Test.assert(false, "Couldn't find an empty slot");
        return false;
    }

    function response0(responseCode, data) { System.println("QueuedComm: response0"); return response(0, responseCode, data); }
    function response1(responseCode, data) { return response(1, responseCode, data); }
    function response2(responseCode, data) { return response(2, responseCode, data); }
    function response3(responseCode, data) { return response(3, responseCode, data); }

    function response(slotIndex, responseCode, responseData) {
        System.println("QueuedComm: handling a response(" + slotIndex + ")");
        var responseMethod = slot[slotIndex][:responseMethod];
        var responseVar = slot[slotIndex][:responseVar];
        slot[slotIndex] = null;
        slotsInUse--;
        responseMethod.invoke(responseVar, responseCode, responseData);
        System.println("QueuedComm: freed slot " + slotIndex + ", slotsInUse=" + slotsInUse);
        if (pendingHead != pendingTail) { makeNextWebRequest(); }
    }
}
