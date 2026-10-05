import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import qs.Commons
import qs.Ui

// Bar entry point for shojey. The player itself is bin/shojey (mpv + MPRIS);
// this widget is the whole UI: a card with a now-playing home view and an
// in-place browser for each source.
//
//   left click    open / close the card
//   right click   play / pause
//   middle click  stop
//   scroll        volume
//
// Keys in the card: space play/pause, ←/→ previous/next, ↑/↓ volume,
// , / . back / forward 10 seconds, g go to a time, f favorite, t sleep timer, b show / hide the sources,
// s/p/r/a/c browse SomaFM/Paradise/Radio/Audius/ccMixter, o songs heard on air, esc back or close.
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
  readonly property string glyphClose: String.fromCodePoint(0xf0156)
  readonly property string glyphRetry: String.fromCodePoint(0xf0450)
  readonly property string glyphSleep: String.fromCodePoint(0xf04b2)
  readonly property string glyphVolume: String.fromCodePoint(0xf057e)
  readonly property string glyphVolumeLow: String.fromCodePoint(0xf057f)
  readonly property string glyphVolumeOff: String.fromCodePoint(0xf0581)
  readonly property string glyphExpand: String.fromCodePoint(0xf0140)
  readonly property string glyphCollapse: String.fromCodePoint(0xf0143)

  readonly property var sources: ({
    soma: { title: "SomaFM", placeholder: "Filter channels", local: true },
    paradise: { title: "Radio Paradise", placeholder: "Filter channels", local: true },
    radio: { title: "Radio", placeholder: "Name, tag or country (top voted shown)" },
    audius: { title: "Audius", placeholder: "Search tracks (trending shown)", queue: true },
    ccmixter: { title: "ccMixter", placeholder: "Search tracks (editor's picks shown)", queue: true },
    favorites: { title: "Favorites", placeholder: "Filter favorites", local: true, saved: true },
    recent: { title: "Recent", placeholder: "Filter recent plays", local: true, saved: true },
    // Songs the live stations announced; picking one copies its title.
    history: { title: "Heard on air", placeholder: "Filter songs", local: true, saved: true, copy: true }
  })

  // mpv-mpris registers every mpv as identity "mpv", so only count the one
  // playing a url shojey started; a video in another mpv is left alone.
  readonly property var player: {
    var known = ({})
    if (current) known[current.url] = true
    for (var q = 0; q < queue.length; q++) if (queue[q]) known[queue[q].url] = true
    var list = Mpris.players ? Mpris.players.values : []
    for (var i = 0; i < list.length; i++) {
      var p = list[i]
      if (!p || String(p.identity || "").toLowerCase() !== "mpv") continue
      var url = p.metadata ? p.metadata["xesam:url"] : undefined
      if (url !== undefined && known[String(url)]) return p
    }
    return null
  }
  readonly property bool playing: player !== null && player.isPlaying

  // shojey's own state: what was started, recent plays, favorites, the queue.
  property var current: null
  property var recent: []
  property var favorites: []
  property var queue: []
  property var history: []
  property var lastError: null          // {entry, message} when playback failed
  property var sleepTimer: null         // {minutes, until} while a sleep timer runs
  property real now: Date.now()
  readonly property int sleepLeft: sleepTimer ? Math.max(1, Math.ceil((sleepTimer.until - now / 1000) / 60)) : 0

  // mpv's own volume, not the system's.
  readonly property real volume: player && player.volumeSupported ? player.volume : 1

  // A track has a timeline to move along; a live stream doesn't.
  readonly property bool seekable: player !== null && !live && player.canSeek && player.length > 0
  // Where a seek is headed, shown until MPRIS reports the new position.
  property real seekTarget: -1
  readonly property real position: seekTarget >= 0 ? seekTarget : (player ? player.position : 0)
  property bool jumping: false          // typing a time to go to

  // The waveform behind the seek bar is how loud shojey's own stream has been
  // over the last second or two, newest on the right.
  readonly property int waveBars: 48
  property var wave: []                 // 0-1 per bar, oldest first
  property var waveRecent: []           // raw levels of the last three seconds
  readonly property bool waveWanted: popupOpen && view === "home" && playing
  // bin/shojey names its mpv stream, which tells it from any other mpv.
  readonly property var stream: {
    var nodes = Pipewire.nodes.values
    for (var i = 0; i < nodes.length; i++) {
      if (nodes[i].isStream && nodes[i].name === "shojey") return nodes[i]
    }
    return null
  }

  // Started but not on MPRIS yet: mpv is still connecting.
  readonly property bool connecting: player === null && current !== null
  readonly property var resumeEntry: recent.length > 0 ? recent[0] : null

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
    // A station names its channel; a track's own name is already the title.
    return entry.live ? entry.source + " · " + entry.name : entry.source
  }
  // Radio Paradise publishes the cover of the song on air; other stations
  // only have a channel logo.
  property string liveCover: ""
  readonly property string artUrl: liveCover || (entry && entry.art ? entry.art : "")

  property bool popupOpen: false

  // While something plays the card is just the player; the sources and the
  // saved lists wait behind "Browse". With nothing playing they are the card.
  property bool expanded: false
  readonly property bool browsable: expanded || (player === null && !connecting)

  // --- browse state ------------------------------------------------------
  property string view: "home"          // "home" | "browse"
  property string browseKind: "soma"    // key of `sources`
  property var results: []
  property string resultsQuery: ""
  property bool loading: false
  property string loadError: ""
  property int selectedIndex: 0
  property int requestSeq: 0

  readonly property var browseList: browseKind === "favorites" ? favorites
    : browseKind === "recent" ? recent
    : browseKind === "history" ? history : results
  readonly property var visibleResults: {
    if (!sources[browseKind].local || !searchField.text) return browseList
    var q = searchField.text.toLowerCase()
    return browseList.filter(function(e) {
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
    errorFile.reload()
    historyFile.reload()
    sleepFile.reload()
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

  // Set over MPRIS so the slider follows live; the script stores the level
  // once it settles, for the next play.
  function setVolume(v) {
    if (!player || !player.volumeSupported) return
    player.volume = Math.max(0, Math.min(1, v))
    volumeSave.restart()
  }

  function seekTo(seconds) {
    if (!seekable) return
    seekTarget = Math.max(0, Math.min(player.length - 1, Math.floor(seconds)))
    shojey(["seek", String(seekTarget)])
    seekSettle.restart()
  }

  function seekBy(seconds) {
    if (!seekable) return
    shojey(["seek", (seconds < 0 ? "-" : "+") + Math.abs(seconds)])
    seekSettle.restart()
  }

  function openJump() {
    if (!seekable) return
    jumpField.text = ""
    jumping = true
    Qt.callLater(function() { jumpField.forceActiveFocus() })
  }

  function closeJump() {
    jumping = false
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  // "3" is minute 3, "3:20" is 3:20; the script says so if the track is shorter.
  function jump(text) {
    text = text.trim()
    if (!/^\d+(:\d{1,2}){0,2}$/.test(text)) return
    shojey(["seek", text.indexOf(":") === -1 ? text + ":00" : text])
    seekSettle.restart()
    closeJump()
  }

  // off → 15 → 30 → 60 minutes → off
  function cycleSleep() {
    var minutes = sleepTimer ? sleepTimer.minutes : 0
    var next = minutes < 15 ? 15 : minutes < 30 ? 30 : minutes < 60 ? 60 : 0
    shojey(["sleep", next ? String(next) : "off"])
  }

  function activateSaved(kind, entry) {
    if (sources[kind].copy) shojey(["copy", entry.name])
    else shojey(["play-saved", entry.url])
  }

  function browse(kind) {
    browseKind = kind
    view = "browse"
    results = []
    resultsQuery = ""
    loadError = ""
    selectedIndex = 0
    searchField.text = ""
    loading = false
    // Favorites and recent come straight from the state files.
    if (!sources[kind].saved) fetchResults("")
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
    if (sources[browseKind].copy) {
      shojey(["copy", list[index].name])
      return
    }
    // Track results play as a queue so next / previous walk the list.
    if (sources[browseKind].saved) shojey(["play-saved", list[index].url])
    else if (sources[browseKind].queue) shojey(["play-list", String(index), JSON.stringify(list)])
    else shojey(["play-json", JSON.stringify(list[index])])
    goHome()
  }

  function removeSaved(entry) {
    if (!entry) return
    if (browseKind === "favorites") shojey(["fav", entry.url])
    else shojey(["forget", entry.url])
  }

  function moveSelection(delta) {
    var count = visibleResults.length
    if (count === 0) return
    selectedIndex = Math.max(0, Math.min(count - 1, selectedIndex + delta))
    resultsView.positionViewAtIndex(selectedIndex, ListView.Contain)
  }

  onPopupOpenChanged: {
    if (popupOpen) {
      now = Date.now()
      reload()
    } else {
      view = "home"
      expanded = false
      wave = []
      waveRecent = []
      jumping = false
      searchDebounce.stop()
    }
  }
  onSeekableChanged: if (!seekable) jumping = false
  onPlayingUrlChanged: {
    liveCover = ""
    seekTarget = -1
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
    id: errorFile
    path: root.runtimeDir + "/error.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.lastError = root.parse(errorFile, null)
    onLoadFailed: root.lastError = null
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

  FileView {
    id: historyFile
    path: root.stateDir + "/history.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.history = root.parse(historyFile, [])
    onLoadFailed: root.history = []
  }

  FileView {
    id: sleepFile
    path: root.runtimeDir + "/sleep.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      root.now = Date.now()
      root.sleepTimer = root.parse(sleepFile, null)
    }
    onLoadFailed: root.sleepTimer = null
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

  PwObjectTracker {
    objects: root.stream ? [root.stream] : []
  }

  PwNodePeakMonitor {
    id: streamLevel
    node: root.stream
    enabled: root.waveWanted && root.stream !== null
  }

  Timer {
    interval: 33
    repeat: true
    running: streamLevel.enabled
    onTriggered: {
      var level = streamLevel.peak
      // Music sits in a narrow band of loudness; stretch the band of the
      // last few seconds over the bar height, so a quiet passage still moves.
      var recent = root.waveRecent.slice(-89)
      recent.push(level)
      root.waveRecent = recent
      var sorted = recent.slice().sort(function(a, b) { return a - b })
      var low = sorted[Math.floor(sorted.length / 10)]
      var range = Math.max(0.15, sorted[sorted.length - 1] - low)
      var next = root.wave.slice(1 - root.waveBars)
      next.push(Math.pow(Math.min(1, Math.max(0, (level - low) / range)), 0.7))
      root.wave = next
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

  Timer {
    id: volumeSave
    interval: 500
    onTriggered: if (root.player) root.shojey(["volume", String(Math.round(root.player.volume * 100))])
  }

  Timer {
    id: seekSettle
    interval: 800
    onTriggered: {
      root.seekTarget = -1
      if (root.player) root.player.positionChanged()
    }
  }

  // Keeps the sleep countdown on the card current.
  Timer {
    interval: 10000
    repeat: true
    running: root.popupOpen && root.sleepTimer !== null
    onTriggered: root.now = Date.now()
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
    onWheelMoved: function(delta) { root.setVolume(root.volume + (delta > 0 ? 0.05 : -0.05)) }
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
      blocked: root.view !== "home" || root.jumping

      onCloseRequested: root.close()
      onActivateRequested: if (root.player) root.player.togglePlaying()
      onMoveRequested: function(dx, dy) {
        if (!root.player) return
        if (dx < 0 && root.player.canGoPrevious) root.player.previous()
        else if (dx > 0 && root.player.canGoNext) root.player.next()
        else if (dy !== 0) root.setVolume(root.volume - dy * 0.05)
      }
      onTextKey: function(text) {
        if (text === "s") root.browse("soma")
        else if (text === "p") root.browse("paradise")
        else if (text === "c") root.browse("ccmixter")
        else if (text === "r") root.browse("radio")
        else if (text === "a") root.browse("audius")
        else if (text === "o") root.browse("history")
        else if (text === ",") root.seekBy(-10)
        else if (text === ".") root.seekBy(10)
        else if (text === "g") root.openJump()
        else if (text === "b") root.expanded = !root.expanded
        else if (text === "f") root.toggleFavorite()
        else if (text === "t" && root.player) root.cycleSleep()
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
              source: root.player ? root.artUrl
                : root.connecting ? (root.current.art || "")
                : root.lastError ? (root.lastError.entry.art || "")
                : root.resumeEntry ? (root.resumeEntry.art || "") : ""
              opacity: root.player || root.connecting ? 1 : 0.5
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
              text: root.player ? (root.title || "Loading…")
                : root.connecting ? root.current.name
                : root.lastError ? "Couldn't play " + root.lastError.entry.name
                : "Nothing playing"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: true
              elide: Text.ElideRight
            }

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: root.player ? root.artist
                : root.connecting ? "Connecting…"
                : root.lastError ? root.lastError.message
                : root.resumeEntry ? "Last played · " + root.resumeEntry.name
                : "Pick a source below"
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

          Button {
            iconText: root.glyphSleep
            text: root.sleepTimer ? root.sleepLeft + "m" : ""
            bordered: true
            foreground: root.sleepTimer ? Color.accent : root.bar.foreground
            tooltipText: root.sleepTimer ? "Stops in " + root.sleepLeft + " min; click to change" : "Sleep timer"
            onClicked: root.cycleSleep()
          }
        }

        // Nothing playing: retry a failed stream, or pick up where you left off.
        Row {
          visible: root.player === null && !root.connecting && (root.lastError !== null || root.resumeEntry !== null)
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.space(6)

          Button {
            visible: root.lastError !== null
            iconText: root.glyphRetry
            text: "Retry"
            bordered: true
            selected: true
            foreground: root.bar.foreground
            onClicked: root.shojey(["play-saved", root.lastError.entry.url])
          }

          Button {
            visible: root.lastError !== null
            iconText: root.glyphClose
            text: "Dismiss"
            bordered: true
            foreground: root.bar.foreground
            onClicked: root.shojey(["dismiss"])
          }

          Button {
            visible: root.lastError === null
            iconText: root.glyphPlay
            text: "Resume"
            bordered: true
            selected: true
            foreground: root.bar.foreground
            onClicked: root.shojey(["resume"])
          }
        }

        Column {
          visible: root.player !== null
          width: parent.width
          spacing: Style.space(4)

          // The seek bar runs through the middle of the waveform.
          Item {
            id: timeline
            width: parent.width
            height: Style.space(44)

            Row {
              id: waveRow
              anchors.centerIn: parent
              height: parent.height
              spacing: Style.space(2)

              readonly property real barWidth: (timeline.width - spacing * (root.waveBars - 1)) / root.waveBars

              Repeater {
                model: root.waveBars

                Rectangle {
                  required property int index
                  // On a track, the part already played is lit.
                  readonly property bool lit: !root.seekable || (index + 0.5) / root.waveBars <= scrubber.progress

                  anchors.verticalCenter: parent.verticalCenter
                  width: waveRow.barWidth
                  height: Math.max(width, (root.wave[root.wave.length - root.waveBars + index] || 0) * timeline.height)
                  radius: width / 2
                  color: lit ? Color.accent : root.bar.foreground
                  opacity: lit ? 0.55 : 0.25
                }
              }
            }

            Rectangle {
              visible: !root.seekable
              anchors.verticalCenter: parent.verticalCenter
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

            // Seeks on release, so dragging doesn't stutter through the track.
            PanelSlider {
              id: scrubber
              visible: root.seekable
              anchors.verticalCenter: parent.verticalCenter
              bar: root.bar
              width: parent.width
              fillColor: Color.accent
              maximum: root.player ? Math.max(1, root.player.length) : 1
              step: 10
              value: root.position
              onReleased: function(v) { root.seekTo(v) }
            }
          }

          Item {
            width: parent.width
            height: root.jumping ? jumpField.implicitHeight : Math.max(liveLabel.implicitHeight, volumeRow.height)

            Text {
              id: liveLabel
              visible: !root.jumping
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: root.live ? "● LIVE"
                : root.player ? root.formatTime(scrubber.dragging ? scrubber.liveValue : root.position) : ""
              color: (root.live && root.playing) || jumpMouse.containsMouse ? Color.accent : Qt.darker(root.bar.foreground, 1.7)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption

              MouseArea {
                id: jumpMouse
                enabled: root.seekable
                anchors.fill: parent
                anchors.margins: -Style.space(4)
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.openJump()
              }
            }

            TextField {
              id: jumpField
              visible: root.jumping
              width: Style.space(110)
              placeholderText: "go to m:ss"
              foreground: root.bar.foreground
              font.family: root.bar.fontFamily

              onActiveFocusChanged: if (!jumpField.activeFocus) root.jumping = false

              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                  root.closeJump()
                  event.accepted = true
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                  root.jump(jumpField.text)
                  event.accepted = true
                }
              }
            }

            // The volume sits between the two times.
            Row {
              id: volumeRow
              visible: !root.jumping && root.player !== null && root.player.volumeSupported
              anchors.centerIn: parent
              height: Style.space(16)
              spacing: Style.space(6)

              Text {
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: root.volume <= 0 ? root.glyphVolumeOff : root.volume < 0.5 ? root.glyphVolumeLow : root.glyphVolume
                color: Qt.darker(root.bar.foreground, 1.7)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
              }

              PanelSlider {
                bar: root.bar
                width: Style.space(110)
                height: parent.height
                anchors.verticalCenter: parent.verticalCenter
                trackHeight: Style.space(2)
                knobSize: Style.space(10)
                fillColor: Color.accent
                value: root.volume
                onMoved: function(v) { root.setVolume(v) }
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: Math.round(root.volume * 100)
                color: Qt.darker(root.bar.foreground, 1.7)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            Text {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: root.live ? (root.playing ? "" : "paused") : (root.player ? root.formatTime(root.player.length) : "")
              color: Qt.darker(root.bar.foreground, 1.7)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }

        Button {
          visible: root.player !== null || root.connecting
          anchors.horizontalCenter: parent.horizontalCenter
          iconText: root.expanded ? root.glyphCollapse : root.glyphExpand
          text: root.expanded ? "Less" : "Browse"
          foreground: Qt.darker(root.bar.foreground, 1.3)
          onClicked: root.expanded = !root.expanded
        }

        // Stations on top, on-demand tracks below.
        Column {
          visible: root.browsable
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
            { kind: "favorites", label: "Favorites", total: root.favorites.length, items: root.favorites.slice(0, 3) },
            { kind: "recent", label: "Recent", total: root.recent.length,
              items: root.recent.filter(function(e) { return e.url !== root.playingUrl }).slice(0, 3) },
            { kind: "history", label: "Heard on air", total: root.history.length,
              items: root.history.filter(function(e) { return e.name !== root.rawTitle }).slice(0, 3) }
          ]

          Column {
            id: savedSection
            required property var modelData
            visible: root.browsable && modelData.items.length > 0
            width: homeColumn.width
            spacing: Style.space(2)

            PanelSeparator { foreground: root.bar.foreground }

            Item {
              width: parent.width
              height: sectionLabel.implicitHeight

              Text {
                id: sectionLabel
                textFormat: Text.PlainText
                text: savedSection.modelData.label
                color: Qt.darker(root.bar.foreground, 1.7)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
              }

              Text {
                anchors.right: parent.right
                textFormat: Text.PlainText
                text: "All " + savedSection.modelData.total + " ›"
                color: allMouse.containsMouse ? Color.accent : Qt.darker(root.bar.foreground, 1.7)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption

                MouseArea {
                  id: allMouse
                  anchors.fill: parent
                  anchors.margins: -Style.space(4)
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.browse(savedSection.modelData.kind)
                }
              }
            }

            Repeater {
              model: modelData.items

              EntryRow {
                required property var modelData
                host: root
                width: homeColumn.width
                entry: modelData
                compact: true
                onClicked: root.activateSaved(savedSection.modelData.kind, modelData)
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
            text: root.loading ? "loading…" : (root.loadError ? "" : root.visibleResults.length + (root.sources[root.browseKind].saved ? " saved" : " results"))
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
            } else if (event.key === Qt.Key_Delete && text === "" && root.sources[root.browseKind].saved) {
              root.removeSaved(root.visibleResults[root.selectedIndex])
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
              removable: root.sources[root.browseKind].saved === true
              onClicked: root.playResult(index)
              onRemoveRequested: root.removeSaved(modelData)
              onHovered: root.selectedIndex = index
            }
          }

          Text {
            anchors.centerIn: parent
            visible: !root.loading && root.visibleResults.length === 0
            textFormat: Text.PlainText
            text: root.loadError || (root.browseKind === "favorites" ? "No favorites yet; use the heart while something plays"
              : root.browseKind === "recent" ? "Nothing played yet"
              : root.browseKind === "history" ? "No songs yet; they show up as stations play" : "Nothing found")
            color: Qt.darker(root.bar.foreground, 1.7)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }
      }
    }
  }
}
