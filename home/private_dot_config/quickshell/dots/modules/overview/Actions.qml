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

    // action: promote | ignore. day and project come from the item, never from its title.
    function untracked(action, item) {
        if (action !== "promote" && action !== "ignore") return false
        if (!item || !/^[0-9]{4}-[0-9]{2}-[0-9]{2}$/.test(String(item.day || ""))) return false
        var p = String(item.project || "")
        if (p === "" || p.charAt(0) === "-") return false
        Quickshell.execDetached(["dots-overview", "untracked", action, String(item.day), p])
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
