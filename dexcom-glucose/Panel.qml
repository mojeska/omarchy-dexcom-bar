import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "dexcom-glucose-settings"
  ipcTarget: "dexcom-glucose.settings"

  property var anchorItem: null
  property var hostWidget: null

  property string username: ""
  property string region: "us"
  property int highThreshold: 180
  property int lowThreshold: 70
  property bool hasPassword: false
  property string passwordInput: ""
  property bool saving: false
  property bool loading: false
  property string errorText: ""

  onOpenedChanged: if (opened) loadConfig()

  function loadConfig() {
    loading = true
    errorText = ""
    passwordInput = ""
    if (!loadProc.running) loadProc.running = true
  }

  function trySave() {
    if (saving || loading) return
    if (username.trim() === "") {
      errorText = "Username is required"
      return
    }
    saving = true
    errorText = ""
    var payload = {
      username: username.trim(),
      region: region,
      highThreshold: highThreshold,
      lowThreshold: lowThreshold,
    }
    if (passwordInput !== "") payload.password = passwordInput
    saveProc.pendingPayload = JSON.stringify(payload)
    // Re-arm stdin each time -- a prior save left it closed (stdinEnabled is
    // explicitly set false below once the payload is written), and a fresh
    // process launch needs it open again.
    saveProc.stdinEnabled = true
    if (!saveProc.running) saveProc.running = true
  }

  Process {
    id: loadProc
    command: ["omarchy-dexcom-status", "--get-config"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.loading = false
        var raw = String(text || "").trim()
        if (!raw) return
        try {
          var parsed = JSON.parse(raw)
          root.username = String(parsed.username || "")
          root.region = String(parsed.region || "us")
          root.highThreshold = Number(parsed.highThreshold) || 180
          root.lowThreshold = Number(parsed.lowThreshold) || 70
          root.hasPassword = parsed.hasPassword === true
        } catch (e) {
          // Leave whatever was already there -- a broken get-config isn't
          // fatal, the user can still fill the form in from scratch.
        }
        Qt.callLater(function() {
          if (root.opened) userField.forceActiveFocus()
        })
      }
    }
  }

  Process {
    id: saveProc
    property string pendingPayload: ""
    command: ["omarchy-dexcom-status", "--set-config"]
    stdinEnabled: true
    stdout: StdioCollector {
      id: saveStdout
      waitForEnd: true
      onStreamFinished: {
        root.saving = false
        var raw = String(text || "").trim()
        var parsed = null
        try { parsed = JSON.parse(raw) } catch (e) {}
        if (parsed && parsed.ok) {
          root.passwordInput = ""
          root.close()
          if (root.hostWidget && typeof root.hostWidget.refresh === "function") root.hostWidget.refresh()
        } else {
          root.errorText = (parsed && parsed.error) || "Save failed"
        }
      }
    }
    onRunningChanged: {
      if (running) {
        saveProc.write(pendingPayload + "\n")
        saveProc.stdinEnabled = false
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(300))
    contentHeight: panel.fittedContentHeight(formColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: true

      Column {
        id: formColumn
        width: parent.width
        spacing: Style.space(12)

        Text {
          textFormat: Text.PlainText
          text: "Dexcom Share"
          color: root.barForeground
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.title
          font.bold: true
        }

        TextField {
          id: userField
          width: parent.width
          foreground: root.barForeground
          placeholderText: "Username or phone"
          text: root.username
          onTextChanged: root.username = text
          Keys.onEscapePressed: root.close()
          onAccepted: root.trySave()
        }

        TextField {
          id: pwField
          width: parent.width
          password: true
          foreground: root.barForeground
          placeholderText: root.hasPassword ? "•••••••• (unchanged)" : "Password"
          text: root.passwordInput
          onTextChanged: root.passwordInput = text
          Keys.onEscapePressed: root.close()
          onAccepted: root.trySave()
        }

        Row {
          spacing: Style.space(8)

          Button {
            id: usButton
            text: "US"
            bordered: true
            selected: root.region === "us"
            focusable: true
            onClicked: root.region = "us"
          }

          Button {
            id: ousButton
            text: "Outside US"
            bordered: true
            selected: root.region === "ous"
            focusable: true
            onClicked: root.region = "ous"
          }
        }

        NumberField {
          id: highField
          label: "High (mg/dL)"
          value: root.highThreshold
          from: 100
          to: 400
          stepSize: 5
          onModified: function(v) { root.highThreshold = v }
        }

        NumberField {
          id: lowField
          label: "Low (mg/dL)"
          value: root.lowThreshold
          from: 40
          to: 100
          stepSize: 5
          onModified: function(v) { root.lowThreshold = v }
        }

        Text {
          visible: root.errorText !== ""
          textFormat: Text.PlainText
          text: root.errorText
          color: root.bar ? root.bar.urgent : Color.urgent
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
          width: parent.width
        }

        Row {
          spacing: Style.space(8)

          Button {
            text: root.saving ? "Saving…" : "Save"
            enabled: !root.saving && !root.loading
            onClicked: root.trySave()
          }

          Button {
            text: "Cancel"
            bordered: true
            enabled: !root.saving
            onClicked: root.close()
          }
        }
      }
    }
  }
}
