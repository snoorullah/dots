pragma Singleton
import QtQuick
import Quickshell

// Every write the overview can make, and nothing else. Each is one detached exec
// of an argv ARRAY (never a shell string), so a title or ref containing quotes,
// semicolons or $() reaches the program as one inert argument.
Singleton {
    // Stable handle for an item: the ref when it has one, else its id.
    function handle(item) {
        if (!item) return ""
        var h = String(item.ref ? item.ref : (item.id ? item.id : ""))
        // A leading "-" would be read as an option by the callee.
        return h.charAt(0) === "-" ? "" : h
    }

    function breakdown(item) {
        var h = handle(item)
        if (h === "") return false
        Quickshell.execDetached(["dots-overview", "breakdown", h, "--start"])
        return true
    }

    // Alert tickets: the agent edits a plain copy; these two are the human's steps after it.
    // Review extracts the patch and opens it read-only. Push is a SEPARATE click and nothing
    // else ever calls it.
    function alertReview(item) {
        var h = handle(item)
        if (h === "") return false
        Quickshell.execDetached(["dots-overview", "alert-review", h])
        return true
    }

    function alertPush(item) {
        var h = handle(item)
        if (h === "") return false
        Quickshell.execDetached(["dots-overview", "alert-push", h])
        return true
    }

    function jump(item) {
        var h = handle(item)
        if (h === "") return false
        Quickshell.execDetached(["dots-jump", h])
        return true
    }

    function report() {
        Quickshell.execDetached(["dots-overview", "report"])
    }

    // action: start | stop | break
    function focus(action) {
        if (action !== "start" && action !== "stop" && action !== "break") return false
        Quickshell.execDetached(["dots-overview", "focus", action])
        return true
    }
}
