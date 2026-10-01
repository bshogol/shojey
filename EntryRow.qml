import QtQuick
import qs.Commons
import qs.Ui

// One playable entry in the shojey card: art (or a glyph), name and detail.
BorderSurface {
  id: row

  // The BarWidget root: bar, glyphs, favorites and what is playing.
  property var host: null
  readonly property color fg: host && host.bar ? host.bar.foreground : Color.foreground
  readonly property string fontFamily: host && host.bar ? host.bar.fontFamily : Style.font.family
  readonly property string playingUrl: host ? host.playingUrl : ""
  readonly property bool playerPlaying: host ? host.playing : false
  readonly property var favorites: host ? host.favorites : []
  function glyph(name) { return host ? host[name] : "" }

  property var entry: null
  property bool compact: false
  property bool selected: false
  // Shows a remove button on hover (favorites and recent views).
  property bool removable: false
  readonly property bool showRemove: removable && (rowMouse.containsMouse || removeMouse.containsMouse || selected)
  readonly property bool isPlaying: entry && entry.url === row.playingUrl
  readonly property bool isFavorite: entry && row.favorites.some(function(f) { return f.url === row.entry.url })

  signal clicked()
  signal hovered()
  signal removeRequested()

  height: (compact ? Style.space(28) : Style.space(44))
  radius: Style.spacing.labelGap
  color: selected || rowMouse.containsMouse ? Style.hoverFillFor(row.fg, Color.accent) : "transparent"
  borderSpec: Border.none()

  Row {
    anchors.fill: parent
    anchors.leftMargin: Style.space(6)
    anchors.rightMargin: Style.space(6)
    spacing: Style.space(10)

    Item {
      width: row.compact ? Style.space(18) : Style.space(34)
      height: width
      anchors.verticalCenter: parent.verticalCenter

      Image {
        id: rowArt
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        sourceSize.width: Style.space(68)
        sourceSize.height: Style.space(68)
        source: !row.compact && row.entry && row.entry.art ? row.entry.art : ""
        visible: status === Image.Ready
      }

      Text {
        anchors.centerIn: parent
        visible: !rowArt.visible
        textFormat: Text.PlainText
        text: row.entry && row.entry.live ? row.glyph("glyphRadio") : row.glyph("glyphIdle")
        color: Color.accent
        font.family: row.fontFamily
        font.pixelSize: row.compact ? Style.font.body : Style.font.subtitle
      }
    }

    Column {
      width: parent.width - (row.compact ? Style.space(18) : Style.space(34)) - Style.space(40)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(1)

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: row.entry ? (row.entry.title || row.entry.name) : ""
        color: row.isPlaying ? Color.accent : row.fg
        font.family: row.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: row.isPlaying
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        visible: !row.compact && text !== ""
        textFormat: Text.PlainText
        text: row.entry ? (row.entry.detail || row.entry.source) : ""
        color: Qt.darker(row.fg, 1.7)
        font.family: row.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }

    Text {
      width: Style.space(24)
      anchors.verticalCenter: parent.verticalCenter
      horizontalAlignment: Text.AlignRight
      textFormat: Text.PlainText
      text: row.showRemove ? row.glyph("glyphClose")
        : row.isPlaying ? (row.playerPlaying ? row.glyph("glyphNote") : row.glyph("glyphPause"))
        : row.isFavorite ? row.glyph("glyphHeart")
        : row.compact && row.entry ? row.entry.source.slice(0, 1) : ""
      color: row.isPlaying || row.isFavorite ? Color.accent : Qt.darker(row.fg, 1.7)
      font.family: row.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  MouseArea {
    id: rowMouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: row.clicked()
    onEntered: row.hovered()
  }

  MouseArea {
    id: removeMouse
    visible: row.removable
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    width: Style.space(40)
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: row.removeRequested()
  }
}
