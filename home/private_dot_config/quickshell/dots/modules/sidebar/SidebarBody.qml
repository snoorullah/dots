pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.theme
import qs.modules.common
import qs.modules.overview
import "parts"
import "js/SideModel.js" as S

// The sidebar's content: the control centre's queue, compact. Pure view over the overview
// feed (read-only); the PanelWindow in Sidebar.qml only places it.
FocusScope {
    id: body

    // data, defaulting to the overview feed
    property var items: Feed.attentionItems.concat(Feed.nextItems)
    property var task: Feed.task
    property string nextTitle: Feed.nextItems.length > 0 ? String(Feed.nextItems[0].title || "") : ""
    property bool dim: Feed.dim
    // view state
    property string tab: "queue"
    property string selectedId: ""
    property bool showSystem: false
    property bool animate: true

    signal expandRequested(string tab)
    signal closeRequested()

    readonly property int panelWidth: 460
    readonly property var shown: S.filterTab(items, tab)
    readonly property var rows: S.group(shown)
    readonly property var selected: {
        for (var i = 0; i < items.length; i++) if (items[i].id === selectedId) return items[i];
        return null;
    }
    readonly property string nowTitle: task ? [task.ref, task.desc].filter(function (s) { return !!s }).join(" ") : ""

    width: panelWidth
    objectName: "sidebarBody"
    Keys.onEscapePressed: body.closeRequested()

    Rectangle {
        anchors.fill: parent
        radius: Theme.radius.card
        color: Qt.alpha(Theme.color.bg, Theme.alpha.panel)
        border.width: 1
        border.color: Theme.color.outlineVariant
    }

    Column {
        anchors.fill: parent
        anchors.margins: 1

        SideHeader {
            id: header
            width: parent.width
            title: body.nowTitle
            next: body.nextTitle
            stale: body.dim
            systemOpen: body.showSystem
            onSystemToggled: body.showSystem = !body.showSystem
        }
        SideTabs {
            id: tabs
            width: parent.width
            current: body.tab
            onPicked: function (key) { body.tab = key; body.showSystem = false }
        }

        Item {
            id: content
            width: parent.width
            height: parent.height - header.height - tabs.height - (footer.visible ? footer.height : 0)
            clip: true

            Flickable {
                id: scroll
                objectName: "sideScroll"
                anchors.fill: parent
                visible: !body.showSystem
                contentHeight: list.implicitHeight + Theme.space.m * 2
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: list
                    x: Theme.space.m
                    y: Theme.space.m
                    width: parent.width - Theme.space.m * 2
                    Repeater {
                        model: body.rows
                        Loader {
                            id: cell
                            required property var modelData
                            width: list.width
                            sourceComponent: modelData.head !== undefined ? headC : rowC
                            Component {
                                id: headC
                                // the caption style of DText, as plain Text: DText's tracked caption
                                // role trips a binding loop on font.letterSpacing
                                Text {
                                    objectName: "groupHead"
                                    topPadding: Theme.space.xl - Theme.space.m + 4
                                    bottomPadding: Theme.space.s
                                    leftPadding: Theme.space.m
                                    text: cell.modelData.head
                                    color: Theme.color.fgDim
                                    font.family: Theme.font.mono
                                    font.pixelSize: Theme.font.size.caption
                                    font.weight: Theme.font.weight.label
                                    font.letterSpacing: Theme.font.size.caption * Theme.font.track.label
                                    lineHeightMode: Text.FixedHeight
                                    lineHeight: Theme.font.line.caption
                                    renderType: Text.NativeRendering
                                }
                            }
                            Component {
                                id: rowC
                                SideRow {
                                    item: cell.modelData.item
                                    dim: body.dim
                                    animate: body.animate
                                    selected: body.selectedId === cell.modelData.item.id
                                    onPicked: body.selectedId = cell.modelData.item.id
                                    onJumped: Actions.jump(cell.modelData.item)
                                }
                            }
                        }
                    }
                }
                DText {
                    objectName: "emptyNote"
                    visible: body.rows.length === 0
                    x: Theme.space.xxl
                    y: Theme.space.xxl
                    text: "Nothing in the queue"
                    role: "bodyS"
                    dim: true
                }
            }

            Item {
                anchors.fill: parent
                visible: body.showSystem
                Loader {
                    id: systemSlot
                    objectName: "systemSlot"
                    anchors.fill: parent
                    active: body.showSystem
                    source: "../system/SystemPanel.qml"
                }
                DText {
                    objectName: "systemMissing"
                    visible: body.showSystem && systemSlot.status !== Loader.Ready
                    x: Theme.space.xxl
                    y: Theme.space.xxl
                    text: "System panel not installed"
                    role: "bodyS"
                    dim: true
                }
            }
        }

        SideFooter {
            id: footer
            visible: !body.showSystem
            width: parent.width
            title: S.pickTitle(body.selected)
            hasSelection: body.selected !== null
            onExpand: body.expandRequested(body.tab)
        }
    }
}
