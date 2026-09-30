import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.Commons
import qs.Ui

// Bar entry point for shojey. The player itself is bin/shojey (mpv + MPRIS);
// this widget is the whole UI: a card with a now-playing home view and an
// in-place browser for each source.
//
//   left click    open / close the card
//   right click   play / pause
//   middle click  stop
//
// Keys in the card: space play/pause, ←/→ previous/next, f favorite,
// s/p/r/a/c browse SomaFM/Paradise/Radio/Audius/ccMixter, esc back or close.
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
  readonly property string glyphBack: String.fromCodePoint(0xf004d)

  readonly property var sources: ({
    soma: { title: "SomaFM", placeholder: "Filter channels", local: true },
    paradise: { title: "Radio Paradise", placeholder: "Filter channels", local: true },
    radio: { title: "Radio", placeholder: "Search stations (top voted shown)" },
    audius: { title: "Audius", placeholder: "Search tracks (trending shown)", queue: true },
    ccmixter: { title: "ccMixter", placeholder: "Search tracks (editor's picks shown)", queue: true }
  })

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
  readonly property string artist: titleSplit > 0 ? rawTitle.slice(0, titleSplit)
    : (player && player.trackArtist ? String(player.trackArtist) : "")
  readonly property string sourceLabel: {
    if (!entry) return ""
    if (entry.source === "Audius") return "Audius"
    return entry.source + " · " + entry.name
  }
  // Radio Paradise publishes the cover of the song on air; other stations
  // only have a channel logo.
  property string liveCover: ""
  readonly property string artUrl: liveCover || (entry && entry.art ? entry.art : "")

  property bool popupOpen: false

  // --- browse state ------------------------------------------------------
  property string view: "home"          // "home" | "browse"
  property string browseKind: "soma"    // key of `sources`
  property var results: []
  property string resultsQuery: ""
  property bool loading: false
  property string loadError: ""
  property int selectedIndex: 0
  property int requestSeq: 0

  readonly property var visibleResults: {
    if (!sources[browseKind].local || !searchField.text) return results
    var q = searchField.text.toLowerCase()
    return results.filter(function(e) {
      return (e.name + " " + (e.detail || "")).toLowerCase().indexOf(q) !== -1
    })
  }

  // Shape the shell's summon/hide/toggle routing expects, so the card can be
  // bound to a key: omarchy-shell shell summon boris.shojey
  readonly property bool opened: popupOpen
  function open() { popupOpen = true }
  function close() { popupOpen = false }

  function shojey(args) {
    Util.execArgv([root.script].concat(args))
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

  function toggleFavorite() {
    if (!root.playingUrl) return
    // A live station is favorited as the station, a track as itself.
    shojey(root.live ? ["fav", root.playingUrl] : ["fav", root.playingUrl, root.rawTitle])
  }

  function browse(kind) {
    browseKind = kind
    view = "browse"
    results = []
    resultsQuery = ""
    loadError = ""
    selectedIndex = 0
    searchField.text = ""
    fetchResults("")
    Qt.callLater(function() { searchField.forceActiveFocus() })
  }

  function goHome() {
    view = "home"
    searchDebounce.stop()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  // One list process at a time. A newer request waits for the running one
  // to exit (it is killed first), so stale output never reaches the view.
  property var pendingRequest: null

  function fetchResults(query) {
    requestSeq += 1
    loading = true
    loadError = ""
    pendingRequest = { seq: requestSeq, kind: browseKind, query: query }
    if (listProc.running) listProc.running = false
    else startPendingRequest()
  }

  function startPendingRequest() {
    var request = pendingRequest
    if (!request) return
    pendingRequest = null
    listProc.seq = request.seq
    listProc.query = request.query
    listProc.command = [root.script, "list", request.kind, request.query]
    listProc.running = true
  }

  function onListOutput(seq, query, text) {
    if (seq !== requestSeq || pendingRequest) return
    loading = false
    try {
      var list = JSON.parse(text)
      results = Array.isArray(list) ? list : []
      resultsQuery = query
      selectedIndex = 0
      resultsView.positionViewAtBeginning()
    } catch (e) {
      results = []
      loadError = "Couldn't load " + sources[browseKind].title
    }
  }

  // Enter while a search is still pending runs it now instead of playing.
  function submit() {
    if (!sources[browseKind].local && searchField.text !== resultsQuery) {
      searchDebounce.stop()
      fetchResults(searchField.text)
      return
    }
    playResult(selectedIndex)
  }

  function playResult(index) {
    var list = visibleResults
    if (index < 0 || index >= list.length) return
    // Track results play as a queue so next / previous walk the list.
    if (sources[browseKind].queue) shojey(["play-list", String(index), JSON.stringify(list)])
    else shojey(["play-json", JSON.stringify(list[index])])
    goHome()
  }

  function moveSelection(delta) {
    var count = visibleResults.length
    if (count === 0) return
    selectedIndex = Math.max(0, Math.min(count - 1, selectedIndex + delta))
    resultsView.positionViewAtIndex(selectedIndex, ListView.Contain)
  }

  onPopupOpenChanged: {
    if (popupOpen) reload()
    else {
      view = "home"
      searchDebounce.stop()
    }
  }
  onPlayingUrlChanged: {
    liveCover = ""
    reload()
  }
  onRawTitleChanged: fetchLiveCover()
  onEntryChanged: fetchLiveCover()

  function fetchLiveCover() {
    liveCover = ""
    coverRetry.stop()
    if (!entry || entry.source !== "Radio Paradise" || !rawTitle) return
    coverProc.running = false
    coverProc.attempts = 0
    coverProc.command = [root.script, "paradise-now", String(entry.chan || "0")]
    coverProc.running = true
  }

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

  Process {
    id: listProc
    running: false
    property int seq: 0
    property string query: ""

    onRunningChanged: if (!running) Qt.callLater(root.startPendingRequest)

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.onListOutput(listProc.seq, listProc.query, text)
    }
  }

  // The API can run a few seconds ahead of or behind the stream, so only
  // take a cover whose song matches what is playing; retry briefly if not.
  Process {
    id: coverProc
    running: false
    property int attempts: 0

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var now = JSON.parse(text)
          if (now.cover && root.rawTitle === now.artist + " - " + now.title) {
            root.liveCover = now.cover
            return
          }
        } catch (e) {}
        if (coverProc.attempts < 3) coverRetry.restart()
      }
    }
  }

  Timer {
    id: coverRetry
    interval: 5000
    onTriggered: {
      coverProc.attempts += 1
      coverProc.running = true
    }
  }

  Timer {
    id: searchDebounce
    interval: 450
    onTriggered: root.fetchResults(searchField.text)
  }

  // MPRIS position is not pushed; poll it while the card shows a track bar.
  Timer {
    interval: 1000
    repeat: true
    running: root.popupOpen && root.view === "home" && root.playing && !root.live
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

  // KeyboardPanel rather than PopupCard: it takes keyboard focus, which the
  // search field needs.
  KeyboardPanel {
    id: panel
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(root.view === "home" ? homeColumn.implicitHeight : browseColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.view !== "home"

      onCloseRequested: root.close()
      onActivateRequested: if (root.player) root.player.togglePlaying()
      onMoveRequested: function(dx, dy) {
        if (!root.player) return
        if (dx < 0 && root.player.canGoPrevious) root.player.previous()
        else if (dx > 0 && root.player.canGoNext) root.player.next()
      }
      onTextKey: function(text) {
        if (text === "s") root.browse("soma")
        else if (text === "p") root.browse("paradise")
        else if (text === "c") root.browse("ccmixter")
        else if (text === "r") root.browse("radio")
        else if (text === "a") root.browse("audius")
        else if (text === "f") root.toggleFavorite()
      }

      // ================= home: now playing ===============================
      Column {
        id: homeColumn
        visible: root.view === "home"
        width: parent.width
        spacing: Style.space(10)

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
            onClicked: root.toggleFavorite()
          }
        }

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

        // Stations on top, on-demand tracks below.
        Column {
          width: parent.width
          spacing: Style.space(6)

          Repeater {
            model: [
              [
                { kind: "soma", glyph: root.glyphRadio, label: "SomaFM" },
                { kind: "paradise", glyph: root.glyphRadio, label: "Paradise" },
                { kind: "radio", glyph: root.glyphSearch, label: "Radio" }
              ],
              [
                { kind: "audius", glyph: root.glyphIdle, label: "Audius" },
                { kind: "ccmixter", glyph: root.glyphIdle, label: "ccMixter" }
              ]
            ]

            Row {
              id: chipRow
              required property var modelData
              width: homeColumn.width
              spacing: Style.space(6)

              readonly property real chipWidth: (width - spacing * (modelData.length - 1)) / modelData.length

              Repeater {
                model: chipRow.modelData

                Button {
                  required property var modelData
                  width: chipRow.chipWidth
                  iconText: modelData.glyph
                  text: modelData.label
                  bordered: true
                  foreground: root.bar.foreground
                  onClicked: root.browse(modelData.kind)
                }
              }
            }
          }
        }

        Repeater {
          model: [
            { label: "Favorites", items: root.favorites.slice(0, 3) },
            { label: "Recent", items: root.recent.filter(function(e) { return e.url !== root.playingUrl }).slice(0, 3) }
          ]

          Column {
            required property var modelData
            visible: modelData.items.length > 0
            width: homeColumn.width
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

              EntryRow {
                required property var modelData
                host: root
                width: homeColumn.width
                entry: modelData
                compact: true
                onClicked: root.shojey(["play-saved", modelData.url])
              }
            }
          }
        }
      }

      // ================= browse: one source ==============================
      Column {
        id: browseColumn
        visible: root.view === "browse"
        width: parent.width
        spacing: Style.space(8)

        Item {
          width: parent.width
          height: backButton.implicitHeight

          Button {
            id: backButton
            iconText: root.glyphBack
            text: root.sources[root.browseKind].title
            foreground: root.bar.foreground
            onClicked: root.goHome()
          }

          Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: root.loading ? "loading…" : (root.loadError ? "" : root.visibleResults.length + " results")
            color: Qt.darker(root.bar.foreground, 1.7)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        TextField {
          id: searchField
          width: parent.width
          placeholderText: root.sources[root.browseKind].placeholder
          foreground: root.bar.foreground
          font.family: root.bar.fontFamily

          onTextChanged: {
            if (root.view !== "browse") return
            root.selectedIndex = 0
            if (!root.sources[root.browseKind].local) searchDebounce.restart()
          }

          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
              root.goHome()
              event.accepted = true
            } else if (event.key === Qt.Key_Down) {
              root.moveSelection(1)
              event.accepted = true
            } else if (event.key === Qt.Key_Up) {
              root.moveSelection(-1)
              event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              root.submit()
              event.accepted = true
            }
          }
        }

        Item {
          width: parent.width
          height: Style.space(320)

          ListView {
            id: resultsView
            anchors.fill: parent
            clip: true
            spacing: Style.space(2)
            boundsBehavior: Flickable.StopAtBounds
            model: root.visibleResults

            delegate: EntryRow {
              required property var modelData
              host: root
              required property int index
              width: resultsView.width
              entry: modelData
              selected: index === root.selectedIndex
              onClicked: root.playResult(index)
              onHovered: root.selectedIndex = index
            }
          }

          Text {
            anchors.centerIn: parent
            visible: !root.loading && root.visibleResults.length === 0
            textFormat: Text.PlainText
            text: root.loadError || "Nothing found"
            color: Qt.darker(root.bar.foreground, 1.7)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }
      }
    }
  }
}
