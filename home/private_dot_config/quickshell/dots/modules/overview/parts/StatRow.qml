import QtQuick
import qs.modules.overview

// label on the left, tabular value on the right
Item {
    id: r
    property string label: ""
    property string value: ""
    property bool dim: false
    property string valueRole: "mono"

    implicitHeight: Math.max(l.implicitHeight, v.implicitHeight)
    implicitWidth: 200

    Txt {
        id: l
        anchors.left: parent.left
        anchors.right: v.left
        anchors.rightMargin: Look.sL
        anchors.verticalCenter: parent.verticalCenter
        text: r.label
        role: "bodyS"
        faint: true
        dim: r.dim
    }
    Txt {
        id: v
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: r.value
        role: r.valueRole
        dim: r.dim
        elide: Text.ElideNone
    }
}
