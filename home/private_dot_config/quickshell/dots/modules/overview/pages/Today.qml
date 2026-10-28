pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.overview
import qs.modules.overview.parts
import "../js/Fmt.js" as Fmt

// Today: time worked, tasks done, by project, by item, by app. Two columns.
FocusScope {
    id: pg
    readonly property var b: Feed.today
    readonly property bool dim: Feed.dim

    function asBars(list, key) {
        return (list || []).map(function (r) { return { name: r[key], sec: r.sec } })
    }

    Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: cols.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Row {
            id: cols
            width: parent.width
            spacing: Look.sXl

            Column {
                width: (parent.width - Look.sXl) / 2
                spacing: Look.sXl

                Row {
                    spacing: Look.sL
                    Txt { text: Fmt.hm(pg.b ? pg.b.workedSec : 0); role: "display"; font.family: Look.mono; dim: pg.dim; elide: Text.ElideNone }
                    StaleMark { visible: pg.dim; anchors.verticalCenter: parent.verticalCenter }
                }
                StatRow { width: parent.width; label: "Tasks done"; value: String(pg.b ? pg.b.tasksDone : 0); dim: pg.dim }
                Txt { text: "By project"; role: "caption"; faint: true; dim: pg.dim }
                Bars { width: parent.width; rows: pg.asBars(pg.b ? pg.b.byProject : [], "project"); dim: pg.dim }
                Empty { visible: !pg.b || !pg.b.byProject || pg.b.byProject.length === 0 }
                Button { text: "Write brief"; icon: "description"; dim: pg.dim; onClicked: Actions.report() }
            }
            Column {
                width: (parent.width - Look.sXl) / 2
                spacing: Look.sXl

                Txt { text: "By item"; role: "caption"; faint: true; dim: pg.dim }
                RefTable { width: parent.width; rows: pg.b ? pg.b.byRef : []; dim: pg.dim }
                Txt { text: "By app"; role: "caption"; faint: true; dim: pg.dim; visible: !!pg.b && !!pg.b.byApp && pg.b.byApp.length > 0 }
                Bars { width: parent.width; rows: pg.asBars(pg.b ? pg.b.byApp : [], "app"); dim: pg.dim }
            }
        }
    }
}
