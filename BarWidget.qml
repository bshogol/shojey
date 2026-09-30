import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.Commons
import qs.Ui

// Bar entry point for shojey. The player itself is bin/shojey (mpv + MPRIS);
// this widget shows a compact now-playing card and launches shojey's menus.
//
//   left click    open / close the card
//   right click   play / pause
//   middle click  stop
BarWidget {
  id: root
  moduleName: "boris.shojey"

  readonly property string script: String(Qt.resolvedUrl("bin/shojey")).replace(/^file:\/\//, "")
  readonly property string runtimeDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/shojey"
  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/shojey"

  readonly property string glyphNote: String.fromCodePoint(0xf075a)
  readonly property string glyphIdle: String.fromCodePoint(0xf0388)
  readonly property string glyphRadio: String.fromCodePoint(0xf0439)
  readonly property string glyphSearch: String.fromCodePoint(0xf0349)
  readonly property string glyphPrev: String.fromCodePoint(0xf04ae)
  readonly property string glyphNext: String.fromCodePoint(0xf04ad)
  readonly property string glyphPlay: String.fromCodePoint(0xf040a)
  readonly property string glyphPause: String.fromCodePoint(0xf03e4)
  readonly property string glyphHeart: String.fromCodePoint(0xf02d1)
  readonly property string glyphHeartOutline: String.fromCodePoint(0xf02d5)

  // mpv-mpris registers as identity "mpv". Any mpv counts, which is fine for
  // a player that only ever runs one mpv; control goes through MPRIS.
  readonly property var player: {
    var list = Mpris.players ? Mpris.players.values : []
    for (var i = 0; i < list.length; i++) {
      if (list[i] && String(list[i].identity || "").toLowerCase() === "mpv") return list[i]
    }
    return null
  }
  readonly property bool playing: player !== null && player.isPlaying

  // shojey's own state: what was started, recent plays, favorites, the queue.
  property var current: null
  property var recent: []
  property var favorites: []
  property var queue: []

  readonly property string playingUrl: player && player.metadata && player.metadata["xesam:url"]
    ? String(player.metadata["xesam:url"]) : (current ? current.url : "")
  readonly property var entry: findEntry(playingUrl)
  readonly property bool live: entry ? entry.live === true : !(player && player.lengthSupported && player.length > 0)
  readonly property bool favorite: favorites.some(function(f) { return f.url === root.playingUrl })

  // Radio streams report "Artist - Song" as one title; split it for the card.
  readonly property string rawTitle: player && player.trackTitle ? String(player.trackTitle) : (entry ? entry.name : "")
  readonly property int titleSplit: rawTitle.indexOf(" - ")
  readonly property string title: titleSplit > 0 ? rawTitle.slice(titleSplit + 3) : rawTitle
  readonly property string artist: titleSplit > 0 ? rawTitle.slice(0, titleSplit) : ""
  readonly property string sourceLabel: {
    if (!entry) return ""
    if (entry.source === "Audius") return "Audius"
    return entry.source + " · " + entry.name
  }
  readonly property string artUrl: entry && entry.art ? entry.art : ""

  property bool popupOpen: false

  // Shape the shell's summon/hide/toggle routing expects, so the card can be
  // bound to a key: omarchy-shell shell summon boris.shojey
  readonly property bool opened: popupOpen
  function open() { popupOpen = true }
  function close() { popupOpen = false }

  function shojey(args) {
    Util.execArgv([root.script].concat(args))
  }

  function openMenu(command) {
    close()
    shojey([command])
  }

  function findEntry(url) {
    if (!url) return null
    var lists = [current ? [current] : [], queue, favorites, recent]
    for (var i = 0; i < lists.length; i++) {
      for (var j = 0; j < lists[i].length; j++) {
        if (lists[i][j] && lists[i][j].url === url) return lists[i][j]
      }
    }
    return null
  }

  function parse(file, fallback) {
    try {
      var value = JSON.parse(file.text())
      return value === null || value === undefined ? fallback : value
    } catch (e) {
      return fallback
    }
  }

  function reload() {
    currentFile.reload()
    recentFile.reload()
    favoritesFile.reload()
    queueFile.reload()
  }

  function formatTime(seconds) {
    seconds = Math.max(0, Math.floor(seconds || 0))
    var s = seconds % 60
    return Math.floor(seconds / 60) + ":" + (s < 10 ? "0" : "") + s
  }

  onPopupOpenChanged: if (popupOpen) reload()
  onPlayingUrlChanged: reload()

  FileView {
    id: currentFile
    path: root.runtimeDir + "/current.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.current = root.parse(currentFile, null)
    onLoadFailed: root.current = null
  }

  FileView {
    id: recentFile
    path: root.stateDir + "/recent.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.recent = root.parse(recentFile, [])
    onLoadFailed: root.recent = []
  }

  FileView {
    id: favoritesFile
    path: root.stateDir + "/favorites.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.favorites = root.parse(favoritesFile, [])
    onLoadFailed: root.favorites = []
  }

  FileView {
    id: queueFile
    path: root.runtimeDir + "/queue.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.queue = root.parse(queueFile, [])
    onLoadFailed: root.queue = []
  }

  // MPRIS position is not pushed; poll it while the card shows a track bar.
  Timer {
    interval: 1000
    repeat: true
    running: root.popupOpen && root.playing && !root.live
    onTriggered: if (root.player) root.player.positionChanged()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.playing ? root.glyphNote : root.glyphIdle
    slotSize: Style.bar.statusSlot
    dimmed: !root.playing
    tooltipText: root.popupOpen ? "" : (root.rawTitle !== "" && root.player ? "shojey · " + root.rawTitle : "shojey")

    onPressed: function(b) {
      if (b === Qt.RightButton) root.shojey(["toggle"])
      else if (b === Qt.MiddleButton) root.shojey(["stop"])
      else root.popupOpen = !root.popupOpen
    }
  }

  PopupCard {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen
    contentWidth: popup.fittedContentWidth(Style.space(330))
    contentHeight: popup.fittedContentHeight(column.implicitHeight)

    Column {
      id: column
      anchors.fill: parent
      spacing: Style.space(10)

      // --- now playing ---------------------------------------------------
      Row {
        width: parent.width
        spacing: Style.space(12)

        BorderSurface {
          width: Style.space(64)
          height: Style.space(64)
          radius: Style.spacing.labelGap
          color: Style.normalFillFor(root.bar.foreground, Color.accent)
          borderSpec: Border.controlSpec("normal", root.bar.foreground, Color.accent)

          Image {
            id: art
            anchors.fill: parent
            anchors.margins: Style.space(2)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            source: root.player ? root.artUrl : ""
            visible: status === Image.Ready
          }

          Text {
            anchors.centerIn: parent
            visible: !art.visible
            text: root.glyphNote
            color: root.player ? Color.accent : root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.displayLarge
          }
        }

        Column {
          width: parent.width - Style.space(76)
          spacing: Style.space(3)
          anchors.verticalCenter: parent.verticalCenter

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: root.player ? (root.title || "Loading…") : "Nothing playing"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.subtitle
            font.bold: true
            elide: Text.ElideRight
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: root.player ? root.artist : "Pick a source below"
            visible: text !== ""
            color: Qt.darker(root.bar.foreground, 1.3)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: root.player ? root.sourceLabel : ""
            visible: text !== ""
            color: Qt.darker(root.bar.foreground, 1.7)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }
      }

      // --- controls ------------------------------------------------------
      Row {
        visible: root.player !== null
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Style.space(6)

        Button {
          iconText: root.glyphPrev
          bordered: true
          foreground: root.bar.foreground
          enabled: root.player && root.player.canGoPrevious
          opacity: enabled ? 1.0 : 0.4
          onClicked: root.player.previous()
        }

        Button {
          iconText: root.playing ? root.glyphPause : root.glyphPlay
          bordered: true
          selected: true
          foreground: root.bar.foreground
          iconSize: Style.font.iconLarge
          horizontalPadding: Style.spacing.panelGap
          onClicked: root.player.togglePlaying()
        }

        Button {
          iconText: root.glyphNext
          bordered: true
          foreground: root.bar.foreground
          enabled: root.player && root.player.canGoNext
          opacity: enabled ? 1.0 : 0.4
          onClicked: root.player.next()
        }

        Button {
          iconText: root.favorite ? root.glyphHeart : root.glyphHeartOutline
          bordered: true
          foreground: root.favorite ? Color.accent : root.bar.foreground
          tooltipText: root.favorite ? "Remove from favorites" : "Add to favorites"
          enabled: root.playingUrl !== ""
          // A live station is favorited as the station, a track as itself.
          onClicked: root.shojey(root.live ? ["fav", root.playingUrl] : ["fav", root.playingUrl, root.rawTitle])
        }
      }

      // --- progress ------------------------------------------------------
      Column {
        visible: root.player !== null
        width: parent.width
        spacing: Style.space(4)

        Rectangle {
          width: parent.width
          height: Style.space(3)
          color: Qt.darker(root.bar.foreground, 4)

          Rectangle {
            height: parent.height
            color: Color.accent
            opacity: root.playing ? 1 : 0.5
            width: root.live ? parent.width
              : root.player && root.player.length > 0 ? parent.width * Math.min(1, root.player.position / root.player.length) : 0
          }
        }

        Item {
          width: parent.width
          height: liveLabel.implicitHeight

          Text {
            id: liveLabel
            textFormat: Text.PlainText
            text: root.live ? "● LIVE" : (root.player ? root.formatTime(root.player.position) : "")
            color: root.live && root.playing ? Color.accent : Qt.darker(root.bar.foreground, 1.7)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            anchors.right: parent.right
            textFormat: Text.PlainText
            text: root.live ? (root.playing ? "" : "paused") : (root.player ? root.formatTime(root.player.length) : "")
            color: Qt.darker(root.bar.foreground, 1.7)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }

      // --- sources -------------------------------------------------------
      Row {
        id: chips
        width: parent.width
        spacing: Style.space(6)

        readonly property real chipWidth: (width - spacing * 2) / 3

        Button {
          width: chips.chipWidth
          iconText: root.glyphRadio
          text: "SomaFM"
          bordered: true
          foreground: root.bar.foreground
          onClicked: root.openMenu("soma")
        }

        Button {
          width: chips.chipWidth
          iconText: root.glyphSearch
          text: "Radio"
          bordered: true
          foreground: root.bar.foreground
          onClicked: root.openMenu("radio")
        }

        Button {
          width: chips.chipWidth
          iconText: root.glyphIdle
          text: "Audius"
          bordered: true
          foreground: root.bar.foreground
          onClicked: root.openMenu("audius")
        }
      }

      // --- favorites & recent --------------------------------------------
      Repeater {
        model: [
          { label: "Favorites", items: root.favorites.slice(0, 3) },
          { label: "Recent", items: root.recent.filter(function(e) { return e.url !== root.playingUrl }).slice(0, 3) }
        ]

        Column {
          required property var modelData
          visible: modelData.items.length > 0
          width: column.width
          spacing: Style.space(2)

          PanelSeparator { foreground: root.bar.foreground }

          Text {
            textFormat: Text.PlainText
            text: modelData.label
            color: Qt.darker(root.bar.foreground, 1.7)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
          }

          Repeater {
            model: modelData.items

            BorderSurface {
              id: savedRow
              required property var modelData

              width: column.width
              height: savedInner.implicitHeight + Style.space(10)
              radius: Style.spacing.labelGap
              color: savedMouse.containsMouse ? Style.hoverFillFor(root.bar.foreground, Color.accent) : "transparent"
              borderSpec: Border.none()

              Row {
                id: savedInner
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(6)
                anchors.rightMargin: Style.space(6)
                spacing: Style.space(8)

                Text {
                  textFormat: Text.PlainText
                  text: savedRow.modelData.live ? root.glyphRadio : root.glyphIdle
                  color: Color.accent
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.body
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  width: parent.width - Style.space(60)
                  textFormat: Text.PlainText
                  text: savedRow.modelData.name
                  color: root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  elide: Text.ElideRight
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  textFormat: Text.PlainText
                  text: savedRow.modelData.source
                  color: Qt.darker(root.bar.foreground, 1.7)
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.caption
                  anchors.verticalCenter: parent.verticalCenter
                }
              }

              MouseArea {
                id: savedMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.shojey(["play-saved", savedRow.modelData.url])
              }
            }
          }
        }
      }
    }
  }
}
