import QtQuick
import Quickshell
import qs.modules.theme as Stub
import "real" as Real

// Prints the stub Theme and the real Tokens.build() side by side as one `AGREE {json}`
// line, then quits. tst/agree.py compares them. Run by tests/overview-ui.sh.
ShellRoot {
    Timer {
        interval: 200
        running: true
        onTriggered: {
            var s = Stub.Theme
            console.log("AGREE " + JSON.stringify({
                stub: { palette: s.palette, color: s.color, alpha: s.alpha, radius: s.radius,
                        space: s.space, font: s.font, bar: s.bar,
                        motion: { fast: s.motion.fast, base: s.motion.base, slow: s.motion.slow } },
                real: Real.Tokens.build()
            }))
            Qt.quit()
        }
    }
}
