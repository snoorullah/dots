import QtQuick

// No data: one quiet line. Never a spinner.
Txt {
    property string line: "nothing on you"
    text: line
    faint: false
    dim: true
    role: "bodyS"
    objectName: "empty"
}
