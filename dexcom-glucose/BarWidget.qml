import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "dexcom-glucose"

  property bool configured: true
  property bool hasReading: false
  property real mgdl: 0
  property string trend: ""
  property string trendArrow: ""
  property string level: "normal"
  property var minutesAgo: null
  property string lastError: ""

  readonly property int refreshSeconds: Math.max(15, parseInt(setting("refreshSeconds", 60), 10) || 60)
  readonly property bool stale: minutesAgo !== null && minutesAgo > 20

  // Morse SOS (··· --- ···) blinked on the reading while it's low, so a red
  // number is hard to miss out of the corner of an eye. One dot = sosUnit;
  // a dash is 3 units, the gap between letters is 3 units, the gap before
  // the pattern repeats is 7 units -- standard Morse timing.
  readonly property int sosUnit: 150
  readonly property bool sosActive: hasReading && level === "low"
  property bool sosOn: true

  readonly property color levelColor: level === "high" ? "orange"
    : level === "low" ? "red"
    : root.bar ? root.bar.barForeground : Color.foreground

  readonly property string displayText: {
    if (!configured) return "Dexcom"
    if (!hasReading) return "––"
    return String(Math.round(mgdl)) + trendArrow
  }

  readonly property string tooltip: {
    if (!configured) return "Dexcom not configured -- left-click to set up"
    if (!hasReading) return lastError || "Fetching…"
    var age = minutesAgo === null ? "" : (" · " + minutesAgo + "m ago")
    return String(Math.round(mgdl)) + " mg/dL · " + (trend || "unknown trend") + age
  }

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  function open() { if (panelLoader.item && panelLoader.item.open) panelLoader.item.open() }
  function close() { if (panelLoader.item && panelLoader.item.close) panelLoader.item.close() }

  visible: true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "dexcom-glucose"

    function refresh(): void {
      root.broadcast("refresh")
    }
  }

  Process {
    id: statusProc
    command: ["omarchy-dexcom-status"]
    stdout: StdioCollector {
      id: statusStdout
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        if (!raw) {
          root.lastError = "no output from omarchy-dexcom-status"
          return
        }
        try {
          var parsed = JSON.parse(raw)
          if (parsed.ok) {
            root.configured = true
            root.hasReading = true
            root.mgdl = Number(parsed.mgdl)
            root.trend = String(parsed.trend || "")
            root.trendArrow = String(parsed.trendArrow || "")
            root.level = String(parsed.level || "normal")
            root.minutesAgo = parsed.minutesAgo === null || parsed.minutesAgo === undefined ? null : Number(parsed.minutesAgo)
            root.lastError = ""
          } else {
            root.lastError = String(parsed.error || "unknown error")
            root.configured = root.lastError !== "not configured"
            if (!root.configured) root.hasReading = false
          }
        } catch (e) {
          root.lastError = "bad response from omarchy-dexcom-status"
        }
      }
    }
  }

  Timer {
    interval: root.refreshSeconds * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  SequentialAnimation {
    running: root.sosActive
    loops: Animation.Infinite

    // S
    PropertyAction { target: root; property: "sosOn"; value: true }
    PauseAnimation { duration: root.sosUnit }
    PropertyAction { target: root; property: "sosOn"; value: false }
    PauseAnimation { duration: root.sosUnit }
    PropertyAction { target: root; property: "sosOn"; value: true }
    PauseAnimation { duration: root.sosUnit }
    PropertyAction { target: root; property: "sosOn"; value: false }
    PauseAnimation { duration: root.sosUnit }
    PropertyAction { target: root; property: "sosOn"; value: true }
    PauseAnimation { duration: root.sosUnit }
    PropertyAction { target: root; property: "sosOn"; value: false }
    PauseAnimation { duration: root.sosUnit * 3 }
    // O
    PropertyAction { target: root; property: "sosOn"; value: true }
    PauseAnimation { duration: root.sosUnit * 3 }
    PropertyAction { target: root; property: "sosOn"; value: false }
    PauseAnimation { duration: root.sosUnit }
    PropertyAction { target: root; property: "sosOn"; value: true }
    PauseAnimation { duration: root.sosUnit * 3 }
    PropertyAction { target: root; property: "sosOn"; value: false }
    PauseAnimation { duration: root.sosUnit }
    PropertyAction { target: root; property: "sosOn"; value: true }
    PauseAnimation { duration: root.sosUnit * 3 }
    PropertyAction { target: root; property: "sosOn"; value: false }
    PauseAnimation { duration: root.sosUnit * 3 }
    // S
    PropertyAction { target: root; property: "sosOn"; value: true }
    PauseAnimation { duration: root.sosUnit }
    PropertyAction { target: root; property: "sosOn"; value: false }
    PauseAnimation { duration: root.sosUnit }
    PropertyAction { target: root; property: "sosOn"; value: true }
    PauseAnimation { duration: root.sosUnit }
    PropertyAction { target: root; property: "sosOn"; value: false }
    PauseAnimation { duration: root.sosUnit }
    PropertyAction { target: root; property: "sosOn"; value: true }
    PauseAnimation { duration: root.sosUnit }
    PropertyAction { target: root; property: "sosOn"; value: false }
    PauseAnimation { duration: root.sosUnit * 7 }
  }

  Item {
    id: blinkWrap
    anchors.fill: parent
    opacity: root.sosActive ? (root.sosOn ? 1 : 0.15) : 1

    WidgetButton {
      id: button
      anchors.fill: parent
      bar: root.bar
      text: root.displayText
      foreground: root.levelColor
      useActiveColor: false
      dimmed: root.stale
      horizontalMargin: 8.75
      fontSize: Style.font.body
      tooltipText: root.tooltip

      onPressed: function(b) {
        if (b === Qt.RightButton) {
          if (root.bar) root.bar.run("omarchy-notification-send \"Dexcom\" \"" + root.tooltip + "\"")
        } else if (b === Qt.MiddleButton) {
          root.open()
        } else if (!root.configured) {
          root.open()
        } else {
          root.refresh()
        }
      }
    }
  }
}
