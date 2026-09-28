import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "local.niri-switch"
  ipcTarget: "local.niri-switch"
  // We define our own IpcHandler below (for refresh), so disable the
  // base-class one to avoid a duplicate-target warning.
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  property string current: "…"
  property string bootTarget: "…"
  property bool niriInstalled: false
  property bool hyprInstalled: true
  property string sessionsText: ""
  property string lastError: ""
  property bool working: false
  property bool switching: false

  readonly property string shortLabel: {
    if (root.current === "Niri") return "Niri"
    if (root.current === "Hyprland") return "Hypr"
    return "WM"
  }

  readonly property string tooltip: {
    var s = "Now: " + root.current + " · Boot: " + root.bootTarget + " · click to switch"
    if (!root.niriInstalled) s += "\nNiri not installed yet"
    return s
  }

  // Absolute helper path (no PATH lookup from QML).
  readonly property string helper: decodeURIComponent(String(Qt.resolvedUrl("switcher.sh")).replace(/^file:\/\//, ""))
  readonly property string bashBin: "/usr/bin/bash"

  function refresh() {
    if (statusProc.running || checkNiriProc.running) return
    root.working = true
    root.lastError = ""
    statusProc.running = true
  }

  function refreshSessions() {
    if (!sessionsProc.running) sessionsProc.running = true
  }

  function doLogout() {
    if (logoutProc.running || root.switching) return
    logoutProc.command = [root.bashBin, "--noprofile", "--norc", root.helper, "logout"]
    logoutProc.running = true
    // Close the popup immediately; the session is going away.
    root.close()
  }

  function doSwitch(dest) {
    if (switchProc.running || logoutProc.running || root.switching) return
    root.switching = true
    root.lastError = ""
    // pkexec pops a GUI auth dialog via the polkit agent; a cancel or
    // failure lands in onExited and re-enables the buttons.
    switchProc.command = [root.bashBin, "--noprofile", "--norc", root.helper, "switch", dest]
    switchProc.running = true
  }

  // Live instances on other monitors stay in sync.
  IpcHandler {
    target: "local.niri-switch"
    function open(): void { root.broadcast("open") }
    function close(): void { root.broadcast("close") }
    function toggle(): void { root.broadcast("toggle") }
    function refresh(): void { root.broadcast("refresh") }
  }

  Process {
    id: statusProc
    command: [root.bashBin, "--noprofile", "--norc", root.helper, "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var t = String(text || "").trim()
        if (t !== "") root.current = t
      }
    }
    stderr: StdioCollector { id: statusErr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        var d = String(statusErr.text || "").trim()
        root.lastError = d !== "" ? d.slice(0, 160) : ("status failed (" + exitCode + ")")
        root.current = "Unknown"
      }
      // Chain: after compositor, check niri presence.
      if (!checkNiriProc.running) {
        checkNiriProc.command = [root.bashBin, "--noprofile", "--norc", root.helper, "is-niri-installed"]
        checkNiriProc.running = true
      } else {
        root.working = false
      }
    }
  }

  Process {
    id: checkNiriProc
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      root.niriInstalled = (exitCode === 0)
      // Chain: after niri check, read the SDDM autologin target.
      if (!targetProc.running) {
        targetProc.command = [root.bashBin, "--noprofile", "--norc", root.helper, "target"]
        targetProc.running = true
      } else {
        root.working = false
      }
    }
  }

  Process {
    id: targetProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var t = String(text || "").trim()
        if (t !== "") root.bootTarget = t
      }
    }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) root.bootTarget = "Unknown"
      root.working = false
      root.refreshSessions()
    }
  }

  Process {
    id: sessionsProc
    command: [root.bashBin, "--noprofile", "--norc", root.helper, "session-names"]
    stdout: StdioCollector {
      id: sessionsOut
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        if (raw === "") {
          root.sessionsText = "No wayland sessions found."
          return
        }
        var lines = raw.split("\n")
        var names = []
        for (var i = 0; i < lines.length; i++) {
          var parts = lines[i].split("|")
          if (parts.length > 0 && parts[0] !== "") names.push("· " + parts[0])
        }
        root.sessionsText = names.join("\n")
      }
    }
    stderr: StdioCollector { waitForEnd: true }
  }

  Process {
    id: logoutProc
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { id: logoutErr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        var d = String(logoutErr.text || "").trim()
        root.lastError = d !== "" ? d.slice(0, 200) : ("logout failed (" + exitCode + ")")
      }
    }
  }

  Process {
    id: switchProc
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { id: switchErr; waitForEnd: true }
    onExited: function(exitCode) {
      // On success the helper already logged out, so the session is gone
      // and the popup closes via doLogout's path. Anything reaching here
      // with nonzero code (auth cancelled, setter missing, …) is an error.
      root.switching = false
      if (exitCode !== 0) {
        var d = String(switchErr.text || "").trim()
        root.lastError = d !== "" ? d.slice(0, 240) : ("switch failed (" + exitCode + ")")
        root.refresh()
      } else {
        root.close()
      }
    }
  }

  Timer {
    interval: 15000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  onOpenedChanged: {
    if (opened) {
      root.refresh()
      Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.shortLabel
    tooltipText: root.tooltip
    onPressed: function() { root.toggle() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(520))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(12)

        PanelHero {
          width: parent.width
          title: "Compositor"
          meta: "Now: " + root.current + " · Boot: " + root.bootTarget + (root.working ? " · checking…" : "")
          detail: root.niriInstalled ? "NIRI READY" : "HYPR ONLY"
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        Text {
          visible: root.lastError !== ""
          width: parent.width
          text: root.lastError
          color: root.bar ? root.bar.urgent : Color.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        PanelSeparator {
          width: parent.width
          foreground: root.foreground
        }

        PanelSectionHeader {
          text: "SWITCH COMPOSITOR"
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        Text {
          width: parent.width
          text: "Switching sets the login target and logs straight back in — no password prompt, no picker. Save work first — windows will close."
          color: Qt.darker(root.foreground, 1.35)
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        Button {
          width: parent.width
          text: root.switching ? "Switching…" : "Switch to Niri + log out"
          iconText: ""
          foreground: root.foreground
          fontFamily: root.fontFamily
          bordered: true
          onClicked: root.doSwitch("niri")
        }

        Button {
          width: parent.width
          text: root.switching ? "Switching…" : "Switch to Hyprland + log out"
          iconText: ""
          foreground: root.foreground
          fontFamily: root.fontFamily
          bordered: true
          onClicked: root.doSwitch("hyprland")
        }

        Button {
          width: parent.width
          text: "Log out (stay on " + root.bootTarget + ")"
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: root.doLogout()
        }

        Button {
          width: parent.width
          text: root.working ? "Checking…" : "Refresh status"
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: root.refresh()
        }

        PanelSeparator {
          width: parent.width
          foreground: root.foreground
        }

        PanelSectionHeader {
          text: "SESSIONS SEEN BY THE SYSTEM"
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        Text {
          width: parent.width
          text: root.sessionsText !== "" ? root.sessionsText : "Loading…"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        Text {
          visible: !root.niriInstalled
          width: parent.width
          text: "Niri isn't installed. Install it with `omarchy pkg add niri` (the omarchy-niri session is already set up), then switch from here."
          color: Qt.darker(root.foreground, 1.35)
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        Text {
          width: parent.width
          text: "Note: under Niri your iNiR shell runs instead of the Omarchy bar, so switch back with: switcher.sh switch hyprland (or `omarchy-niri-switch hyprland` if aliased)."
          color: Qt.darker(root.foreground, 1.35)
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }
      }
    }
  }
}
