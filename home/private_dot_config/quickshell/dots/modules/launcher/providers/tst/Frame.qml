import QtQuick
import "modules/theme"
import "modules/common"

// Test-only stand-in for the launcher core: it draws the card of the boards (field, mode chips, list or
// grid, preview, actions, footer, toast, confirm card) from a provider's row model, so every board state
// can be rendered and measured without the core. objectNames are what the probes in
// tests/launcher-modes.sh read. The real core draws from the same model.
Item {
  id: f

  property var p: null
  property string prefix: ""
  property string query: ""
  property int sel: 0
  property string toast: ""
  property var confirm: null
  property var closed: null
  property bool actionsOpen: false
  property string layoutKind: "list"
  property string modeName: ""
  property bool expand: false

  readonly property var rows: p ? (p.rows || []) : []
  readonly property var row: rows.length > 0 ? rows[Math.max(0, Math.min(sel, rows.length - 1))] : null
  readonly property var chips: [["All", "squares-four"], ["Clipboard", "clipboard-text"], ["Dictionary", "book-open-text"], ["Files", "folder"],
                                ["Fonts + icons", "text-aa"], ["Windows", "stack"], ["Snippets", "note"], ["Emoji", "smiley"],
                                ["SSH hosts", "terminal-window"], ["Kube", "cube"], ["Commands", "terminal-window"], ["Math", "calculator"]]
  readonly property var tone: ({ warn: Theme.color.waiting, danger: Theme.color.failed, accent: Theme.color.accent, muted: Theme.color.fgDim })
  readonly property bool prodCurrent: rows.length > 0 && rows[0].current === true && rows[0].tier === "prod"

  function esc(s) { return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;"); }
  function marked(title, hl) {
    if (!hl || hl.length === 0) return esc(title);
    var out = "", t = String(title);
    for (var i = 0; i < t.length; i++)
      out += hl.indexOf(i) >= 0 ? "<font color='" + Theme.color.accent + "'><b>" + esc(t[i]) + "</b></font>" : esc(t[i]);
    return out;
  }
  function sections() {
    var res = [], cur = null;
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].group || cur === null) { cur = { label: rows[i].group || "", cells: [] }; res.push(cur); }
      cur.cells.push({ r: rows[i], i: i });
    }
    return res;
  }
  function kindWord(r) { return r && r.tierLabel ? r.tierLabel : ""; }

  width: 1000
  height: 620

  Rectangle {
    id: card
    objectName: "frameCard"
    anchors.fill: parent
    radius: Theme.radius.card
    color: Qt.alpha(Theme.color.surface, Theme.alpha.panel)
    border.width: 1
    border.color: Qt.alpha(Theme.color.outline, Theme.alpha.divider)
    clip: true

    Rectangle {   // thin rule when the current context is prod
      objectName: "prodRule"
      visible: f.prodCurrent
      width: parent.width
      height: 3
      color: Theme.color.failed
    }

    // ---- field -------------------------------------------------------------------------
    Item {
      id: field
      x: 16; y: 12; width: card.width - 32; height: 48
      Icon { x: 0; anchors.verticalCenter: parent.verticalCenter; name: "magnifying-glass"; size: 20; color: Theme.color.fgDim }
      Rectangle {
        id: pfx
        objectName: "prefixChip"
        visible: f.prefix !== ""
        x: 32; anchors.verticalCenter: parent.verticalCenter
        width: pfxT.implicitWidth + 16; height: 26; radius: Theme.radius.chip
        color: Qt.alpha(Theme.color.accent, 0.16)
        DText { id: pfxT; objectName: "prefixText"; anchors.centerIn: parent; text: f.prefix; role: "bodyS"; mono: true; color: Theme.color.accent }
      }
      DText {
        objectName: "fieldText"
        x: pfx.visible ? pfx.x + pfx.width + 10 : 32
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - x - 140
        elide: Text.ElideRight
        role: "title"
        text: f.query !== "" ? f.query : "Type to search, or press Tab to change mode."
        dim: f.query === ""
      }
      Row {
        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; spacing: 6
        Repeater {
          model: ["Super", "Space"]
          Rectangle {
            width: kt.implicitWidth + 14; height: 24; radius: Theme.radius.chip
            color: Theme.color.surfaceContainer; border.width: 1; border.color: Qt.alpha(Theme.color.outline, Theme.alpha.divider)
            DText { id: kt; anchors.centerIn: parent; text: modelData; role: "caption"; mono: true; color: Theme.color.fgDim; font.capitalization: Font.MixedCase }
          }
        }
      }
      Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Qt.alpha(Theme.color.outline, Theme.alpha.divider) }
    }

    // ---- mode chips --------------------------------------------------------------------
    Flickable {
      id: chipBar
      x: 16; y: 66; width: card.width - 32; height: 34
      contentWidth: chipRow.width; contentHeight: height
      interactive: false; clip: true
      contentX: Math.max(0, Math.min(chipRow.width - width, activeX - 120))
      property real activeX: 0
      Row {
        id: chipRow
        spacing: 6
        Repeater {
          model: f.chips
          Rectangle {
            objectName: "modeChip"
            property bool on: modelData[0] === f.modeName || (f.modeName === "" && modelData[0] === "All")
            property string label: modelData[0]
            height: 30; width: ci.width + cl.implicitWidth + 28; radius: 15
            color: on ? Theme.color.surfaceContainerHigh : "transparent"
            border.width: on ? 1 : 0; border.color: Qt.alpha(Theme.color.accent, 0.5)
            onOnChanged: if (on) chipBar.activeX = x
            Component.onCompleted: if (on) chipBar.activeX = x
            Icon { id: ci; x: 10; anchors.verticalCenter: parent.verticalCenter; width: 16; name: modelData[1]; size: 16; color: parent.on ? Theme.color.accent : Theme.color.fgDim }
            DText { id: cl; x: 32; anchors.verticalCenter: parent.verticalCenter; text: modelData[0]; role: "bodyS"; color: parent.on ? Theme.color.fg : Theme.color.fgDim }
          }
        }
      }
    }

    // ---- banner / strips -----------------------------------------------------------------
    Item {
      id: bannerBox
      x: 16; y: 104; width: card.width - 32
      readonly property var b: f.p && f.p.banner ? f.p.banner : null
      readonly property bool strip: f.p && f.p.mismatch === true
      readonly property bool note: f.p && f.p.note === "updated"
      height: (b || strip) ? 44 : (note ? 24 : 0)
      Rectangle {
        objectName: "banner"
        property string text: bannerBox.b ? bannerBox.b.title : (bannerBox.strip ? "Shell and screen point at different clusters" : "")
        visible: bannerBox.b !== null || bannerBox.strip
        anchors.fill: parent; radius: Theme.radius.row
        color: Qt.alpha(bannerBox.strip ? Theme.color.waiting : (bannerBox.b ? f.tone[bannerBox.b.tone] : Theme.color.fgDim), 0.12)
        border.width: 1
        border.color: Qt.alpha(bannerBox.strip ? Theme.color.waiting : (bannerBox.b ? f.tone[bannerBox.b.tone] : Theme.color.fgDim), 0.5)
        Icon { x: 12; anchors.verticalCenter: parent.verticalCenter; name: bannerBox.strip ? "warning" : (bannerBox.b && bannerBox.b.tone === "danger" ? "warning" : (bannerBox.b && bannerBox.b.tone === "warn" ? "eye-slash" : "info")); size: 18
          color: bannerBox.strip ? Theme.color.waiting : (bannerBox.b ? f.tone[bannerBox.b.tone] : Theme.color.fgDim) }
        DText {
          x: 38; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 50; elide: Text.ElideRight; role: "bodyS"
          text: bannerBox.strip ? "Shell: " + f.p.shellContext + ". On screen: " + f.p.viewContext + ". One key aligns either side."
                                : (bannerBox.b ? bannerBox.b.title + ". " + bannerBox.b.detail : "")
        }
      }
      DText { objectName: "updatedNote"; visible: bannerBox.note && !bannerBox.b; text: "updated"; role: "caption"; x: 4; anchors.verticalCenter: parent.verticalCenter }
    }

    // ---- body ------------------------------------------------------------------------------
    Item {
      id: body
      x: 0; y: 104 + bannerBox.height + 8; width: card.width; height: card.height - y - 40 - (f.layoutKind === "grid" ? 46 : 0)
      visible: f.closed === null && !(f.p && f.p.adding === true)

      // list
      Item {
        id: listBox
        x: 16; width: f.layoutKind === "grid" ? 480 : 440; height: parent.height
        clip: true

        DText {
          objectName: "errorRow"
          visible: f.p && f.p.error !== ""
          x: 12; y: 12; width: parent.width - 24; wrapMode: Text.Wrap
          color: Theme.color.failed; text: f.p ? f.p.error : ""
        }
        DText {
          objectName: "hintLine"
          visible: f.rows.length === 0 && f.p && f.p.error === ""
          x: 12; y: 12; width: parent.width - 24; wrapMode: Text.Wrap; dim: true
          text: f.p ? (f.p.kubeState === "nokube" || f.p.hint !== "" ? f.p.hint : "Nothing here yet") : ""
        }

        Column {
          id: listCol
          visible: f.layoutKind === "list" && (!f.p || f.p.error === "")
          width: parent.width
          Repeater {
            model: f.rows
            Item {
              id: rowItem
              width: listCol.width
              readonly property bool isSel: index === f.sel
              height: (modelData.group ? 28 : 0) + (modelData.indent ? 34 : 50)
              opacity: modelData.dim ? 0.45 : 1
              DText {
                objectName: "groupHead"
                visible: !!modelData.group
                x: 12; y: 4; text: modelData.group || ""; role: "caption"
              }
              Rectangle {
                objectName: "row"
                property string text: modelData.title
                y: modelData.group ? 28 : 0
                x: modelData.indent ? 28 : 0
                width: parent.width - x; height: modelData.indent ? 32 : 48; radius: Theme.radius.row
                color: rowItem.isSel ? Qt.alpha(Theme.color.fg, 0.10) : "transparent"
                Icon { id: rIcon; x: 12; anchors.verticalCenter: parent.verticalCenter; name: modelData.icon || ""; size: 18; width: 18
                  color: rowItem.isSel ? Theme.color.accent : Theme.color.fgDim }
                Rectangle { // tier chip first, so PROD is read before the name
                  id: tierChip
                  objectName: "tierChip"
                  property string text: modelData.tierLabel || ""
                  visible: !!modelData.tierLabel
                  x: 40; anchors.verticalCenter: parent.verticalCenter
                  width: visible ? tt.implicitWidth + 14 : 0; height: 20
                  radius: modelData.tier === "prod" ? 3 : 10
                  color: modelData.tier === "prod" ? Theme.color.failed : "transparent"
                  border.width: modelData.tier === "prod" ? 0 : 1
                  border.color: modelData.tier === "staging" ? Theme.color.accent : (modelData.tier === "unset" ? Theme.color.waiting : Theme.color.fgFaint)
                  DText { id: tt; anchors.centerIn: parent; text: modelData.tierLabel || ""; role: "caption"; font.letterSpacing: 0
                    color: modelData.tier === "prod" ? Theme.color.bg : (modelData.tier === "staging" ? Theme.color.accent : (modelData.tier === "unset" ? Theme.color.waiting : Theme.color.fgDim)) }
                }
                Column {
                  x: 40 + (tierChip.visible ? tierChip.width + 8 : 0); anchors.verticalCenter: parent.verticalCenter
                  width: parent.width - x - rightBox.width - 20
                  Text {
                    objectName: "rowTitle"
                    property string plain: modelData.title
                    width: parent.width; elide: Text.ElideRight; textFormat: Text.StyledText
                    text: f.marked(modelData.title, modelData.hl)
                    color: Theme.color.fg; font.family: Theme.font.mono; font.pixelSize: Theme.font.size.body
                    renderType: Text.NativeRendering
                  }
                  DText { visible: !modelData.indent; width: parent.width; elide: Text.ElideRight; text: modelData.sub || ""; role: "caption"; font.capitalization: Font.MixedCase; font.letterSpacing: 0; color: Theme.color.fgDim }
                }
                Row {
                  id: rightBox
                  anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter; spacing: 6
                  Repeater {
                    model: modelData.tierLabel ? [] : (modelData.chips || [])
                    Rectangle {
                      objectName: "rowChip"
                      property string text: modelData.t
                      height: 20; width: cc.implicitWidth + 14; radius: 10; color: Qt.alpha(f.tone[modelData.tone] || Theme.color.fgDim, 0.10)
                      border.width: 1; border.color: Qt.alpha(f.tone[modelData.tone] || Theme.color.fgDim, 0.6)
                      DText { id: cc; anchors.centerIn: parent; text: modelData.t; role: "caption"; font.capitalization: Font.MixedCase; font.letterSpacing: 0; color: f.tone[modelData.tone] || Theme.color.fgDim }
                    }
                  }
                  Rectangle { visible: modelData.reach !== undefined; width: 8; height: 8; radius: 4; anchors.verticalCenter: parent.verticalCenter
                    color: modelData.reach === "unk" ? Theme.color.fgFaint : Theme.color.accent }
                  Icon { visible: modelData.current === true && modelData.tier !== undefined; name: "check"; size: 16; color: Theme.color.accent }
                  DText { visible: !!modelData.last; text: modelData.last || ""; role: "caption"; font.capitalization: Font.MixedCase; font.letterSpacing: 0; color: Theme.color.fgDim }
                  DText { visible: rowItem.isSel && !modelData.indent; text: "Enter"; role: "caption"; font.capitalization: Font.MixedCase; font.letterSpacing: 0; color: Theme.color.accent }
                }
              }
            }
          }
        }

        // grid (emoji): sections of 8 cells, 56 px each
        Column {
          visible: f.layoutKind === "grid" && (!f.p || f.p.error === "")
          width: parent.width
          Repeater {
            model: f.layoutKind === "grid" ? f.sections() : []
            Column {
              Item { width: 1; height: modelData.label ? 26 : 0
                DText { objectName: "groupHead"; visible: !!modelData.label; x: 4; anchors.verticalCenter: parent.verticalCenter; text: modelData.label; role: "caption" } }
              Grid {
                columns: 8
                Repeater {
                  model: modelData.cells
                  Rectangle {
                    objectName: "cell"
                    property string text: modelData.r.glyph || ""
                    width: 56; height: 52; radius: Theme.radius.row
                    color: modelData.i === f.sel ? Qt.alpha(Theme.color.fg, 0.12) : "transparent"
                    border.width: modelData.i === f.sel ? 1 : 0; border.color: Qt.alpha(Theme.color.accent, 0.6)
                    Text { anchors.centerIn: parent; text: modelData.r.glyph || ""; font.pixelSize: 26
                      font.family: "Noto Color Emoji, Noto Sans Symbols 2, Noto Sans Symbols, DejaVu Sans"; color: Theme.color.fg }
                    Rectangle { visible: modelData.r.tofu === true; width: 6; height: 6; radius: 3; color: Theme.color.waiting; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 6 }
                  }
                }
              }
            }
          }
        }
      }

      // preview
      Rectangle {
        id: pv
        objectName: "preview"
        x: listBox.x + listBox.width + 8; width: card.width - x - 16; height: parent.height
        radius: Theme.radius.row; color: Qt.alpha(Theme.color.surfaceContainer, 0.7)
        border.width: 1; border.color: Qt.alpha(Theme.color.outline, Theme.alpha.divider)
        clip: true
        visible: f.row !== null && (!f.p || f.p.error === "")
        readonly property var pr: f.row ? f.row.preview : null

        Rectangle { // prod banner on the preview card
          objectName: "prodBanner"
          visible: f.row !== null && f.row.tier === "prod"
          width: parent.width; height: 30; color: Qt.alpha(Theme.color.failed, 0.18)
          DText { x: 14; anchors.verticalCenter: parent.verticalCenter; text: "PROD. Look first, then switch."; role: "bodyS"; color: Theme.color.failed }
        }
        Flickable {
          anchors.fill: parent; anchors.topMargin: (f.row && f.row.tier === "prod") ? 30 : 0; anchors.bottomMargin: 64
          contentHeight: pcol.height + 20; clip: true; interactive: false
          Column {
            id: pcol
            x: 18; y: 16; width: parent.width - 36; spacing: 10
            Image {
              objectName: "previewImage"
              visible: !!(pv.pr && pv.pr.image)
              width: parent.width; height: visible ? 150 : 0; fillMode: Image.PreserveAspectFit; horizontalAlignment: Image.AlignLeft
              source: pv.pr && pv.pr.image ? "file://" + pv.pr.image : ""
            }
            Text {
              objectName: "previewGlyph"
              visible: !!(pv.pr && pv.pr.glyph)
              text: pv.pr && pv.pr.glyph ? pv.pr.glyph : ""; font.pixelSize: 64
              font.family: "Noto Color Emoji, Noto Sans Symbols 2, Noto Sans Symbols, DejaVu Sans"; color: Theme.color.fg
            }
            Icon { objectName: "previewIcon"; visible: !!(pv.pr && pv.pr.icon); name: pv.pr && pv.pr.icon ? pv.pr.icon : ""; size: 48; width: 48; height: 48; color: Theme.color.fg }
            Text {
              objectName: "previewHead"
              visible: !(pv.pr && pv.pr.glyph)
              width: parent.width; wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight
              text: pv.pr ? pv.pr.head : ""
              color: Theme.color.fg
              font.family: pv.pr && pv.pr.font ? pv.pr.font : Theme.font.mono
              font.pixelSize: pv.pr && pv.pr.font ? 36 : 20
              font.weight: Font.Medium
              renderType: Text.NativeRendering
            }
            Text {
              objectName: "previewBody"
              width: parent.width; wrapMode: Text.Wrap; maximumLineCount: 12; elide: Text.ElideRight
              text: pv.pr ? pv.pr.body : ""
              color: Theme.color.fgDim; font.pixelSize: Theme.font.size.bodyS; lineHeight: 1.25
              renderType: Text.NativeRendering
              font.family: pv.pr && pv.pr.font ? Theme.font.sans : Theme.font.mono
            }
            Flow {
              width: parent.width; spacing: 6
              visible: !!(pv.pr && pv.pr.fields && pv.pr.fields.length)
              Repeater {
                model: pv.pr && pv.pr.fields ? pv.pr.fields : []
                Rectangle {
                  objectName: "fieldChip"
                  property string text: modelData.name + "=" + modelData.value + ":" + modelData.state
                  property color c: modelData.state === "empty" || modelData.state === "warn" ? Theme.color.waiting : Theme.color.accent
                  height: 24; width: fcT.implicitWidth + 16; radius: 6
                  color: modelData.state === "filled" ? Qt.alpha(c, 0.18) : (modelData.state === "ghost" ? Qt.alpha(c, 0.07) : (modelData.state === "builtin" ? Theme.color.surfaceContainerHigh : Qt.alpha(c, 0.12)))
                  border.width: 1; border.color: modelData.state === "builtin" ? Theme.color.fgFaint : c
                  DText { id: fcT; anchors.centerIn: parent; role: "caption"; font.capitalization: Font.MixedCase; font.letterSpacing: 0; color: parent.c
                    font.italic: modelData.state === "ghost"
                    text: modelData.name + (modelData.value !== "" ? ": " + modelData.value : "  needed") }
                }
              }
            }
            Column {
              width: parent.width; spacing: 4
              visible: !!(pv.pr && pv.pr.panes && pv.pr.panes.length)
              DText { text: "PANES"; role: "caption" }
              Repeater {
                model: pv.pr && pv.pr.panes ? pv.pr.panes : []
                Row {
                  objectName: "panePreview"
                  spacing: 8
                  Rectangle { width: 8; height: 8; radius: 4; anchors.verticalCenter: parent.verticalCenter
                    color: modelData.st === "waiting" ? Theme.color.waiting : (modelData.st === "running" ? Theme.color.accent : Theme.color.fgFaint) }
                  DText { text: modelData.t; role: "bodyS" }
                  DText { visible: modelData.st !== ""; text: modelData.st; role: "caption"; font.capitalization: Font.MixedCase; font.letterSpacing: 0 }
                }
              }
            }
          }
        }
        // action buttons
        Row {
          id: actRow
          x: 18; y: parent.height - 52; spacing: 8
          Repeater {
            model: f.row ? f.row.actions.slice(0, f.layoutKind === "grid" ? 4 : 3) : []
            Rectangle {
              objectName: "actionBtn"
              property string text: modelData.label
              height: 36; width: at.implicitWidth + 28; radius: Theme.radius.row
              opacity: modelData.disabled ? 0.45 : 1
              color: index === 0 ? (modelData.danger ? Theme.color.failed : Theme.color.accent) : Theme.color.surfaceContainer
              border.width: index === 0 ? 0 : 1; border.color: Qt.alpha(Theme.color.outline, Theme.alpha.divider)
              DText { id: at; anchors.centerIn: parent; text: modelData.label; role: "bodyS"; font.weight: index === 0 ? Font.DemiBold : Font.Normal
                color: index === 0 ? Theme.color.accentFg : Theme.color.fg }
            }
          }
          DText { visible: f.row && f.row.actions.length > (f.layoutKind === "grid" ? 4 : 3); anchors.verticalCenter: parent.verticalCenter
            text: "+" + (f.row ? f.row.actions.length - (f.layoutKind === "grid" ? 4 : 3) : 0) + " more"; role: "caption"; font.capitalization: Font.MixedCase; font.letterSpacing: 0 }
        }
      }

      // full action panel (hosts)
      Rectangle {
        objectName: "actionPanel"
        visible: f.actionsOpen && f.row !== null
        x: pv.x + 10; y: 10; width: pv.width - 20; height: apCol.height + 16
        radius: Theme.radius.row; color: Theme.color.surfaceContainerHigh; border.width: 1; border.color: Qt.alpha(Theme.color.outline, Theme.alpha.divider)
        Column {
          id: apCol
          x: 8; y: 8; width: parent.width - 16
          Repeater {
            model: f.row ? f.row.actions : []
            Rectangle {
              objectName: "panelAction"
              property string text: modelData.label
              width: apCol.width; height: 32; radius: 8
              color: index === 0 ? Qt.alpha(Theme.color.fg, 0.10) : "transparent"
              opacity: modelData.disabled ? 0.5 : 1
              DText { x: 10; anchors.verticalCenter: parent.verticalCenter; text: (index + 1) + "   " + modelData.label; role: "bodyS"; color: modelData.danger ? Theme.color.failed : Theme.color.fg }
            }
          }
        }
      }
    }


    // ---- add / edit snippet (Ctrl+N): two fields inline, no manager window --------------------
    Rectangle {
      objectName: "addPanel"
      visible: f.p && f.p.adding === true
      x: 16; y: 104; width: card.width - 32; height: card.height - 104 - 48
      radius: Theme.radius.row; color: Qt.alpha(Theme.color.surfaceContainer, 0.7)
      border.width: 1; border.color: Qt.alpha(Theme.color.outline, Theme.alpha.divider)
      readonly property var d: f.p && f.p.draft ? f.p.draft : ({})
      Column {
        x: 20; y: 18; width: parent.width - 40; spacing: 12
        DText { text: "Save a snippet from the clipboard"; role: "title" }
        Row {
          spacing: 12
          Repeater {
            model: [["Abbreviation", "abbr"], ["Kind", "kind"], ["Title", "title"]]
            Column {
              spacing: 4
              DText { text: modelData[0]; role: "caption" }
              Rectangle {
                objectName: "addField"
                property string text: modelData[1] + "=" + (addPanelRef.d[modelData[1]] || "")
                width: modelData[1] === "title" ? 380 : 150; height: 36; radius: Theme.radius.row; color: Theme.color.surfaceContainer
                border.width: 1; border.color: modelData[1] === "abbr" ? Theme.color.accent : Qt.alpha(Theme.color.outline, Theme.alpha.divider)
                DText { x: 12; anchors.verticalCenter: parent.verticalCenter; text: addPanelRef.d[modelData[1]] || ""; mono: true }
              }
            }
          }
        }
        DText { text: "Text"; role: "caption" }
        Rectangle {
          objectName: "addText"
          property string text: addPanelRef.d.text || ""
          width: parent.width; height: 120; radius: Theme.radius.row; color: Theme.color.surfaceContainer
          border.width: 1; border.color: Qt.alpha(Theme.color.outline, Theme.alpha.divider)
          DText { x: 12; y: 10; width: parent.width - 24; wrapMode: Text.Wrap; text: addPanelRef.d.text || "(empty)"; mono: true; dim: !addPanelRef.d.text }
        }
        Rectangle {
          objectName: "sensitiveCard"
          visible: f.p && f.p.sensitiveHold === true
          width: parent.width; height: 56; radius: Theme.radius.row; color: Qt.alpha(Theme.color.waiting, 0.12)
          border.width: 1; border.color: Theme.color.waiting
          Icon { x: 14; anchors.verticalCenter: parent.verticalCenter; name: "shield-check"; size: 20; color: Theme.color.waiting }
          DText { x: 44; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 60; wrapMode: Text.Wrap
            text: (f.p ? f.p.sensitiveReason : "") + " It is never previewed. Pattern checks miss things. Enter again saves anyway." }
        }
      }
      Item { id: addPanelRef; property var d: parent.d }
    }

    // ---- closed card (locked or Salah: the core draws it, providers are not queried) --------
    Rectangle {
      objectName: "closedCard"
      visible: f.closed !== null
      anchors.centerIn: parent; width: 520; height: 190; radius: Theme.radius.card
      color: Theme.color.surfaceContainer; border.width: 1; border.color: Qt.alpha(Theme.color.outline, Theme.alpha.divider)
      Column {
        anchors.centerIn: parent; width: parent.width - 48; spacing: 10
        Icon { name: "lock"; size: 28; width: 28; height: 28; color: Theme.color.accent }
        DText { objectName: "closedTitle"; width: parent.width; role: "title"; text: f.closed ? f.closed.title : "" }
        DText { width: parent.width; wrapMode: Text.Wrap; dim: true; text: f.closed ? f.closed.detail : "" }
        Rectangle { visible: !!(f.closed && f.closed.button); height: 34; width: cb.implicitWidth + 28; radius: Theme.radius.row; color: Theme.color.surfaceContainerHigh
          DText { id: cb; anchors.centerIn: parent; text: f.closed ? f.closed.button : ""; role: "bodyS" } }
      }
    }

    // ---- footer ---------------------------------------------------------------------------
    Item {
      x: 16; y: card.height - 36; width: card.width - 32; height: 28
      Rectangle { y: -4; width: parent.width; height: 1; color: Qt.alpha(Theme.color.outline, Theme.alpha.divider) }
      DText { objectName: "footLeft"; anchors.verticalCenter: parent.verticalCenter; role: "caption"; font.capitalization: Font.MixedCase; font.letterSpacing: 0
        text: f.closed ? "Esc closes" : (f.rows.length > 0 ? f.rows.length + (f.rows.length === 1 ? " result" : " results") : (f.p ? f.p.hint : "")) }
      DText { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; role: "caption"; font.capitalization: Font.MixedCase; font.letterSpacing: 0
        text: "Nav N/E move  ·  Enter use  ·  Tab mode  ·  Esc close" }
    }

    // tray (emoji)
    Rectangle {
      objectName: "tray"
      visible: f.layoutKind === "grid" && f.p && f.p.tray !== undefined && f.closed === null
      x: 16; y: card.height - 78; width: card.width - 32; height: 36; radius: Theme.radius.row; color: Theme.color.surfaceContainer
      Row {
        x: 12; anchors.verticalCenter: parent.verticalCenter; spacing: 8
        DText { objectName: "trayLabel"; text: f.p && f.p.tray && f.p.tray.length ? "TRAY" : "Tray empty. Add a glyph with Ctrl+Space."; role: f.p && f.p.tray && f.p.tray.length ? "caption" : "bodyS"; dim: true }
        Repeater {
          model: f.p && f.p.tray ? f.p.tray : []
          Text { objectName: "trayItem"; text: modelData; font.pixelSize: 22; font.family: "Noto Color Emoji, Noto Sans Symbols 2, DejaVu Sans"; color: Theme.color.fg }
        }
      }
    }

    // ---- toast ----------------------------------------------------------------------------
    Rectangle {
      objectName: "toast"
      property string text: f.toast
      visible: f.toast !== ""
      anchors.horizontalCenter: parent.horizontalCenter; y: card.height - 82
      height: 36; width: tl.implicitWidth + 52; radius: 18
      color: Theme.color.surfaceContainerHigh; border.width: 1
      border.color: f.prodCurrent ? Theme.color.failed : Qt.alpha(Theme.color.outline, Theme.alpha.divider)
      Icon { x: 14; anchors.verticalCenter: parent.verticalCenter; name: "check"; size: 16; color: Theme.color.accent }
      DText { id: tl; x: 38; anchors.verticalCenter: parent.verticalCenter; text: f.toast; role: "bodyS" }
    }

    // ---- confirm card ---------------------------------------------------------------------
    Rectangle {
      objectName: "confirmScrim"
      visible: f.confirm !== null
      anchors.fill: parent; color: Qt.alpha(Theme.color.bg, 0.55)
      Rectangle {
        objectName: "confirmCard"
        anchors.centerIn: parent; width: 460; height: 210; radius: Theme.radius.card
        color: Theme.color.surfaceContainer; border.width: f.confirm && f.confirm.danger ? 2 : 1
        border.color: f.confirm && f.confirm.danger ? Theme.color.failed : Qt.alpha(Theme.color.outline, Theme.alpha.divider)
        Column {
          x: 24; y: 22; width: parent.width - 48; spacing: 10
          DText { objectName: "confirmTitle"; width: parent.width; wrapMode: Text.Wrap; role: "headline"; text: f.confirm ? f.confirm.title : "" }
          DText { width: parent.width; wrapMode: Text.Wrap; dim: true; text: f.confirm ? f.confirm.detail : "" }
        }
        Row {
          x: 24; y: parent.height - 56; spacing: 10
          Rectangle { objectName: "confirmGo"; height: 36; width: gt.implicitWidth + 32; radius: Theme.radius.row
            color: f.confirm && f.confirm.danger ? Theme.color.failed : Theme.color.accent
            DText { id: gt; anchors.centerIn: parent; text: (f.confirm ? f.confirm.label : "") + "  Enter"; role: "bodyS"; font.weight: Font.DemiBold; color: Theme.color.accentFg } }
          Rectangle { objectName: "confirmPeek"; visible: !!(f.confirm && f.confirm.alt); height: 36; width: pt.implicitWidth + 32; radius: Theme.radius.row; color: Theme.color.surfaceContainerHigh
            DText { id: pt; anchors.centerIn: parent; text: f.confirm && f.confirm.alt ? f.confirm.alt.label : ""; role: "bodyS" } }
          Rectangle { height: 36; width: xt.implicitWidth + 32; radius: Theme.radius.row; color: Theme.color.surfaceContainerHigh
            DText { id: xt; anchors.centerIn: parent; text: "Cancel  Esc"; role: "bodyS" } }
        }
      }
    }
  }
}
