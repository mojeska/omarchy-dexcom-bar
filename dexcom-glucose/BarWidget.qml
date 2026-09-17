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

  readonly property color levelColor: level === "high" ? "purple"
    : level === "low" ? "red"
    : root.bar ? root.bar.barForeground : Color.foreground

  readonly property string displayText: {
    if (!configured) return "Dexcom"
    if (!hasReading) return "––"
    return String(Math.round(mgdl)) + trendArrow
  }

  readonly property string tooltip: {
    if (!configured) return "Dexcom not configured -- edit ~/.config/omarchy/dexcom.json"
    if (!hasReading) return lastError || "Fetching…"
    var age = minutesAgo === null ? "" : (" · " + minutesAgo + "m ago")
    return String(Math.round(mgdl)) + " mg/dL · " + (trend || "unknown trend") + age
  }

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  visible: true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

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

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.displayText
    foreground: root.levelColor
    useActiveColor: false
    dimmed: root.stale
    slotSize: Style.bar.statusSlot
    fontSize: Style.font.body
    tooltipText: root.tooltip

    onPressed: function(b) {
      if (b === Qt.RightButton) {
        if (root.bar) root.bar.run("omarchy-notification-send \"Dexcom\" \"" + root.tooltip + "\"")
      } else {
        root.refresh()
      }
    }
  }
}
