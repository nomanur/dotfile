import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

Panel {
  id: root
  moduleName: "io.github.nomanur.dotsync"
  ipcTarget: "io.github.nomanur.dotsync"
  manageIpc: false

  // State properties
  property var telemetry: ({})
  property string remoteUrl: ""
  property string branch: "main"
  property bool isSsh: true
  property bool isClean: true
  property int modifiedCount: 0
  property int aheadCount: 0
  property int behindCount: 0
  property var filesList: []
  property var lastCommit: null
  property string lastSyncTime: ""
  property bool isInitialized: true

  // Action states
  property bool isBusy: false
  property bool isPushing: false
  property bool isPulling: false
  property string lastMessage: ""
  property bool isError: false

  readonly property string helperPath: decodeURIComponent(
    String(Qt.resolvedUrl("bin/dotsync-ctl")).replace(/^file:\/\//, "")
  )

  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color accent: Commons.Color.accent
  readonly property color dimForeground: Qt.darker(foreground, 1.45)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function updateStatus(data) {
    root.telemetry = data
    root.isInitialized = data.initialized !== false
    root.remoteUrl = data.remote_url || ""
    root.branch = data.branch || "main"
    root.isSsh = data.is_ssh === true
    root.isClean = data.clean === true
    root.modifiedCount = data.modified_count || 0
    root.aheadCount = data.ahead || 0
    root.behindCount = data.behind || 0
    root.filesList = data.files || []
    root.lastCommit = data.last_commit || null
    root.lastSyncTime = data.last_sync || ""
  }

  function refresh() {
    if (!statusProc.running) {
      statusProc.running = true
    }
  }

  function runAction(args, actionType) {
    if (actionProc.running) return
    root.isBusy = true
    if (actionType === "push") root.isPushing = true
    else if (actionType === "pull") root.isPulling = true
    root.lastMessage = ""
    root.isError = false
    actionProc.command = [root.helperPath].concat(args)
    actionProc.running = true
  }

  function doPush(customMsg) {
    var args = ["push"]
    if (customMsg && customMsg.trim().length > 0) {
      args.push("-m", customMsg.trim())
    }
    runAction(args, "push")
  }

  function doPull() {
    runAction(["pull"], "pull")
  }

  function saveRemote(url) {
    if (!url || url.trim().length === 0) return
    runAction(["set-remote", url.trim()], "remote")
  }

  function toggleSsh() {
    runAction(["toggle-ssh"], "remote")
  }

  onOpenedChanged: {
    if (opened) {
      root.refresh()
    }
  }

  Process {
    id: statusProc
    command: [root.helperPath, "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var parsed = JSON.parse(text)
          if (parsed && parsed.ok) {
            root.updateStatus(parsed)
          }
        } catch (e) {
          console.warn("DotSync status parse error:", e)
        }
      }
    }
  }

  Process {
    id: actionProc
    command: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.isBusy = false
        root.isPushing = false
        root.isPulling = false
        try {
          var parsed = JSON.parse(text)
          if (parsed.ok) {
            root.lastMessage = parsed.message || "Operation completed successfully"
            root.isError = false
            Quickshell.execDetached(["notify-send", "-a", "Omarchy DotSync", "Git Sync", root.lastMessage])
          } else {
            root.lastMessage = parsed.error || "Operation failed"
            root.isError = true
            Quickshell.execDetached(["notify-send", "-u", "critical", "-a", "Omarchy DotSync", "Git Sync Error", root.lastMessage])
          }
        } catch (e) {
          root.lastMessage = text
          root.isError = true
        }
        root.refresh()
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (text && text.trim().length > 0) {
          console.warn("DotSync stderr:", text)
        }
      }
    }
  }

  Timer {
    interval: 20000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  IpcHandler {
    target: "io.github.nomanur.dotsync"
    function open() { root.open() }
    function close() { root.close() }
    function show() { root.open() }
    function hide() { root.close() }
    function toggle() { root.toggle() }
    function refresh() { root.refresh() }
    function push() { root.doPush("") }
    function pull() { root.doPull() }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\uf09b"
    labelText: root.modifiedCount > 0 ? String(root.modifiedCount) : (root.aheadCount > 0 ? "↑" + root.aheadCount : "")
    active: root.opened
    tooltipText: {
      var state = root.isClean ? "All configs synced" : (root.modifiedCount + " modified config(s) pending push")
      if (root.aheadCount > 0) state += " · " + root.aheadCount + " unpushed commit(s)"
      if (root.behindCount > 0) state += " · " + root.behindCount + " commit(s) behind"
      return "Omarchy Git Sync (" + root.branch + ")\n" + state + "\nClick to open · Right-click to refresh"
    }

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) {
        root.refresh()
      } else {
        root.toggle()
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    contentWidth: Style.space(420)
    contentHeight: Style.space(490)

    content: Component {
      PanelKeyCatcher {
        id: keyCatcher
      anchors.fill: parent
      blocked: repoInput.activeFocus || commitMsgInput.activeFocus
      onCloseRequested: root.close()

      Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: mainContent.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: mainContent
          width: flick.width
          spacing: Style.space(12)

          // Header Hero
          PanelHero {
            id: hero
            width: parent.width
            title: "Omarchy Git Sync"
            meta: root.remoteUrl ? (root.branch + " · " + (root.isClean ? "Up to date" : root.modifiedCount + " pending changes")) : "No GitHub repo configured"
            iconComponent: Component {
              Text {
                textFormat: Text.PlainText
                text: "\uf09b"
                font.family: root.fontFamily
                font.pixelSize: Style.font.title * 1.4
                color: root.accent
                anchors.verticalCenter: parent ? parent.verticalCenter : undefined
              }
            }
            trailingControl: Component {
              Button {
                iconText: "󰑐"
                iconSpinning: statusProc.running || root.isBusy
                tooltipText: "Refresh Git Status"
                onClicked: root.refresh()
              }
            }
          }

          PanelSeparator { foreground: root.foreground }

          // Status Banner
          BorderSurface {
            width: parent.width
            radius: Style.cornerRadius
            color: root.isClean ? Qt.rgba(0.1, 0.6, 0.2, 0.12) : Qt.rgba(0.9, 0.6, 0.1, 0.12)
            border.color: root.isClean ? Qt.rgba(0.2, 0.8, 0.3, 0.35) : Qt.rgba(0.9, 0.6, 0.1, 0.35)
            border.width: 1
            padding: Style.space(10)

            Column {
              width: parent.width
              spacing: Style.space(4)

              RowLayout {
                width: parent.width
                spacing: Style.space(8)

                Text {
                  textFormat: Text.PlainText
                  text: root.isClean ? "󰄬" : "󰛃"
                  color: root.isClean ? "#4ade80" : "#fbbf24"
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                }

                Text {
                  textFormat: Text.PlainText
                  text: root.isClean ? "Repository is up to date" : (root.modifiedCount + " configuration files changed")
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                  Layout.fillWidth: true
                }

                Text {
                  textFormat: Text.PlainText
                  text: root.branch
                  color: root.dimForeground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              RowLayout {
                width: parent.width
                visible: root.aheadCount > 0 || root.behindCount > 0 || root.lastSyncTime !== ""
                spacing: Style.space(12)

                Text {
                  textFormat: Text.PlainText
                  visible: root.aheadCount > 0
                  text: "↑ " + root.aheadCount + " unpushed"
                  color: "#60a5fa"
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }

                Text {
                  textFormat: Text.PlainText
                  visible: root.behindCount > 0
                  text: "↓ " + root.behindCount + " behind remote"
                  color: "#f87171"
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }

                Item { Layout.fillWidth: true }

                Text {
                  textFormat: Text.PlainText
                  visible: root.lastSyncTime !== ""
                  text: "Synced: " + root.lastSyncTime
                  color: root.dimForeground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }
          }

          // GitHub Repository Link Section
          Column {
            width: parent.width
            spacing: Style.space(6)

            PanelSectionHeader {
              text: "GITHUB REPOSITORY LINK"
              foreground: root.foreground
            }

            RowLayout {
              width: parent.width
              spacing: Style.space(6)

              TextField {
                id: repoInput
                Layout.fillWidth: true
                text: root.remoteUrl
                placeholderText: "git@github.com:username/repo.git or https://..."
                font.pixelSize: Style.font.caption
                onAccepted: root.saveRemote(repoInput.text)
              }

              Button {
                text: "Save"
                bordered: true
                onClicked: root.saveRemote(repoInput.text)
              }
            }

            RowLayout {
              width: parent.width
              spacing: Style.space(8)

              Text {
                textFormat: Text.PlainText
                text: root.isSsh ? "󰄬 SSH Authenticated (Passwordless push)" : "ℹ HTTPS URL (Requires git credentials)"
                color: root.isSsh ? "#4ade80" : root.dimForeground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                Layout.fillWidth: true
              }

              Button {
                visible: root.remoteUrl !== ""
                text: root.isSsh ? "Use HTTPS" : "Use SSH Key"
                fontSize: Style.font.caption
                onClicked: {
                  root.toggleSsh()
                  Qt.callLater(function() {
                    repoInput.text = root.remoteUrl
                  })
                }
              }
            }
          }

          PanelSeparator { foreground: root.foreground }

          // Sync Actions Section
          Column {
            width: parent.width
            spacing: Style.space(8)

            PanelSectionHeader {
              text: "ACTIONS"
              foreground: root.foreground
            }

            TextField {
              id: commitMsgInput
              width: parent.width
              placeholderText: "Commit message (optional, defaults to timestamp)"
              font.pixelSize: Style.font.caption
              onAccepted: root.doPush(commitMsgInput.text)
            }

            RowLayout {
              width: parent.width
              spacing: Style.space(8)

              Button {
                id: pushBtn
                Layout.fillWidth: true
                text: root.isPushing ? "Pushing to GitHub..." : "Push to GitHub"
                iconText: root.isPushing ? "󰑐" : "󰛃"
                iconSpinning: root.isPushing
                selected: true
                accent: Commons.Color.accent
                onClicked: {
                  root.doPush(commitMsgInput.text)
                  commitMsgInput.text = ""
                }
              }

              Button {
                id: pullBtn
                Layout.fillWidth: true
                text: root.isPulling ? "Pulling..." : "Pull from GitHub"
                iconText: root.isPulling ? "󰑐" : "󰛀"
                iconSpinning: root.isPulling
                bordered: true
                onClicked: root.doPull()
              }
            }
          }

          // Operation Feedback Banner (if any)
          BorderSurface {
            visible: root.lastMessage !== ""
            width: parent.width
            radius: Style.cornerRadius
            color: root.isError ? Qt.rgba(0.9, 0.2, 0.2, 0.15) : Qt.rgba(0.2, 0.8, 0.4, 0.15)
            border.color: root.isError ? Qt.rgba(0.9, 0.2, 0.2, 0.4) : Qt.rgba(0.2, 0.8, 0.4, 0.4)
            border.width: 1
            padding: Style.space(8)

            RowLayout {
              width: parent.width
              spacing: Style.space(6)

              Text {
                textFormat: Text.PlainText
                text: root.isError ? "󰅙" : "󰄬"
                color: root.isError ? "#ef4444" : "#22c55e"
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
              }

              Text {
                textFormat: Text.PlainText
                text: root.lastMessage
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.Wrap
                Layout.fillWidth: true
              }
            }
          }

          // Modified Files List (if any changes)
          Column {
            visible: root.filesList.length > 0
            width: parent.width
            spacing: Style.space(4)

            PanelSectionHeader {
              text: "PENDING CHANGES (" + root.filesList.length + ")"
              foreground: root.foreground
            }

            Repeater {
              model: root.filesList

              delegate: Item {
                width: parent.width
                implicitHeight: Style.space(22)

                RowLayout {
                  anchors.fill: parent
                  spacing: Style.space(8)

                  Text {
                    textFormat: Text.PlainText
                    text: modelData.status || "M"
                    color: modelData.status === "A" ? "#4ade80" : (modelData.status === "D" ? "#ef4444" : "#f59e0b")
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }

                  Text {
                    textFormat: Text.PlainText
                    text: modelData.path || ""
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideMiddle
                    Layout.fillWidth: true
                  }
                }
              }
            }
          }

          // Last Commit Footer
          RowLayout {
            visible: root.lastCommit !== null
            width: parent.width
            spacing: Style.space(6)

            Text {
              textFormat: Text.PlainText
              text: "󰊢 Last commit:"
              color: root.dimForeground
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Text {
              textFormat: Text.PlainText
              text: root.lastCommit ? (root.lastCommit.hash + " " + root.lastCommit.message) : ""
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
              Layout.fillWidth: true
            }
          }
        }
      }
    }
  }
}
}
