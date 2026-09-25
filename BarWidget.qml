// TrafficFlow Tracking in the Omarchy bar — the macOS menubar app, for Hyprland.
//
// Two buttons, exactly like the Mac item: the WAVE (a play/pause glyph here) and
// the TIME. Wave: left-press pauses the running timer or resumes today's last
// entry; time: left-press opens the compact tracker as a floating popover. On
// either, right-press opens the full app and middle-press refreshes.
//
// What it shows it was TOLD by bin/trafficflow-status (a personal API token,
// hours only — this widget never sees a rate or an amount). "Unknown" is a state
// it renders — a dimmed clock with no number and a tooltip that says why — never
// a zero it cannot stand behind.
//
// Polling mirrors the Mac app's adaptive cadence, because the database bills
// for awake-time: every 30s while a tracker window is open, every
// `runningIntervalMs` (60s) while a timer runs, and NOT AT ALL when idle — then
// it refreshes only on interaction (press, tracker window opened/closed). The
// clock itself ticks client-side, so the bar never freezes while the API rests.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "trafficflow.tracker"

  // ── state ──────────────────────────────────────────────────────────────────
  // NOT `state`: QtQuick's Item already owns that name.
  property string sourceState: "unknown"
  property string code: ""
  property string why: "not asked yet"
  property int todayBaseSeconds: 0
  property bool running: false
  property double runningStartedMs: 0
  property int runningBaseSeconds: 0
  property string runningLabel: ""
  property double nowMs: Date.now()
  property bool toggling: false
  // "" (live) | "running" | "idle" — fixed data, no network; for screenshots.
  property string demoMode: ""
  // Hyprland addresses of the tracker's own windows (compact popover, full app).
  property var trackerAddresses: []
  readonly property bool trackerOpen: trackerAddresses.length > 0

  readonly property string baseUrl: String(root.setting("baseUrl", "https://tracking.trafficflow.ch")).replace(/\/+$/, "")
  readonly property string host: baseUrl.replace(/^https?:\/\//, "").replace(/\/.*$/, "")
  // The plugin's own directory, resolved from this file's URL: a third-party
  // plugin's scripts are not on PATH, so every command is addressed absolutely.
  readonly property string binDir: Qt.resolvedUrl("bin/").toString().replace(/^file:\/\//, "")

  readonly property int elapsedSeconds: running ? Math.max(0, Math.floor((nowMs - runningStartedMs) / 1000)) : 0
  readonly property int runningSeconds: runningBaseSeconds + elapsedSeconds
  readonly property int todaySeconds: todayBaseSeconds + elapsedSeconds

  function hmm(total) {
    var h = Math.floor(total / 3600)
    var m = Math.floor((total % 3600) / 60)
    return h + ":" + (m < 10 ? "0" : "") + m
  }

  // Nerd Font glyphs, spelled as escapes: private-use characters pasted as
  // literals are invisible in a diff when a tool between here and the shell
  // mangles them.  play ·  pause ·  clock.
  readonly property string glyph: sourceState !== "ok" ? "" : (running ? "" : "")
  // The Mac title: the running timer's elapsed while tracking, else today's total.
  readonly property string clock: sourceState === "ok" ? hmm(running ? runningSeconds : todaySeconds) : ""

  // ── adaptive polling ───────────────────────────────────────────────────────
  readonly property int pollInterval: trackerOpen ? 30000
    : (running ? Math.max(15000, Number(root.setting("runningIntervalMs", 60000)) || 60000) : 0)

  function refresh() {
    if (statusProc.running) return
    statusProc.stale = false
    statusProc.running = true
  }

  // Parse one status/toggle answer into state. Anything that is not a clean
  // "ok" object is "unknown", with its reason — never a made-up number.
  function adopt(text) {
    var next = { state: "unknown", code: "bad-json", why: "the status source did not answer JSON" }
    try {
      var parsed = JSON.parse(text)
      if (parsed && typeof parsed === "object") next = parsed
    } catch (e) {}
    root.nowMs = Date.now()
    if (next.state === "ok") {
      root.sourceState = "ok"
      root.code = ""
      root.why = ""
      root.todayBaseSeconds = parseInt(next.today_base_seconds, 10) || 0
      var r = next.running
      if (r && typeof r === "object") {
        var started = Date.parse(String(r.started_at))
        root.runningStartedMs = isNaN(started) ? Date.now() : started
        root.runningBaseSeconds = parseInt(r.base_seconds, 10) || 0
        root.runningLabel = (r.project_code ? "[" + r.project_code + "]" : String(r.project_name || ""))
          + " · " + String(r.task_name || "")
        root.running = true
      } else {
        root.running = false
        root.runningLabel = ""
        root.runningBaseSeconds = 0
      }
    } else {
      root.sourceState = "unknown"
      root.code = next.code ? String(next.code) : ""
      root.why = next.why ? String(next.why) : "no answer"
      root.running = false
    }
  }

  // The Mac wave click: stop if running, else resume today's last entry — and
  // when there is nothing to resume, open the tracker so a task can be picked.
  function toggle() {
    if (root.demoMode !== "") {
      root.setDemo(root.demoMode === "running" ? "idle" : "running")
      return
    }
    if (root.sourceState !== "ok") { root.summon(); return }
    if (root.toggling || toggleProc.running) return
    root.toggling = true
    toggleProc.running = true
  }

  function adoptToggle(text) {
    var parsed = null
    try { parsed = JSON.parse(text) } catch (e) {}
    if (parsed && parsed.state === "ok") {
      // Every bar surface gets the new state at once; a poll in flight on this
      // instance is disowned so it cannot overwrite the answer just received.
      statusProc.stale = statusProc.running
      root.relay("adopt", text)
      return
    }
    if (parsed && parsed.code === "nothing-to-resume") { root.summon(); root.refresh(); return }
    root.adopt(text)
  }

  function setDemo(mode) {
    root.demoMode = (mode === "running" || mode === "idle") ? mode : ""
    statusProc.stale = statusProc.running
    root.refresh()
  }

  // `broadcast` from the base class, but carrying an argument: an IPC target
  // routes to ONE handler while a widget is instantiated once per bar surface.
  function relay(method, arg) {
    var items = root.bar && typeof root.bar.moduleWidgets === "function"
      ? root.bar.moduleWidgets(root.moduleName) : [root]
    for (var i = 0; i < items.length; i++) {
      if (items[i] && typeof items[i][method] === "function") items[i][method](arg)
    }
  }

  function summon() { if (root.bar) root.bar.run(root.binDir + "trafficflow-summon") }
  function openApp() { if (root.bar) root.bar.run(root.binDir + "trafficflow-app") }

  // Chromium names an app window `chrome-<host>__<path>-Default`: the compact
  // popover and the full app both start with `chrome-<host>__`.
  function isTrackerClass(cls) { return String(cls).indexOf("chrome-" + root.host + "__") === 0 }

  function noteWindowOpened(address) {
    if (root.trackerAddresses.indexOf(address) >= 0) return
    var next = root.trackerAddresses.slice(); next.push(address)
    root.trackerAddresses = next          // reassign: `var` mutations do not notify
    root.refresh()                        // fresh the moment it opens (Mac: popoverShown)
  }
  function noteWindowClosed(address) {
    var i = root.trackerAddresses.indexOf(address)
    if (i < 0) return
    var next = root.trackerAddresses.slice(); next.splice(i, 1)
    root.trackerAddresses = next
    if (next.length === 0) root.refresh() // it may have started/stopped something inside
  }

  implicitWidth: row.implicitWidth
  implicitHeight: row.implicitHeight

  IpcHandler {
    target: "trafficflow.tracker"
    function refresh(): void { root.broadcast("refresh") }
    function toggle(): void { root.toggle() }
    function open(): void { root.summon() }
    function app(): void { root.openApp() }
    function demo(mode: string): void { root.relay("setDemo", mode) }
  }

  Process {
    id: statusProc
    property bool stale: false
    command: root.demoMode !== ""
      ? [root.binDir + "trafficflow-status", "--demo", root.demoMode]
      : [root.binDir + "trafficflow-status", "--base", root.baseUrl]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (statusProc.stale) { statusProc.stale = false; return }
        root.adopt(text)
      }
    }
  }

  Process {
    id: toggleProc
    command: [root.binDir + "trafficflow-toggle", "--base", root.baseUrl]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: { root.toggling = false; root.adoptToggle(text) }
    }
  }

  // The poll. `running` is the whole adaptive rule: no interval, no timer.
  Timer {
    id: pollTimer
    interval: root.pollInterval > 0 ? root.pollInterval : 60000
    running: root.pollInterval > 0 && root.demoMode === ""
    repeat: true
    onTriggered: root.refresh()
  }

  // Client-side clock while tracking; nothing periodic when idle.
  Timer {
    interval: 1000
    running: root.running && root.sourceState === "ok"
    repeat: true
    onTriggered: root.nowMs = Date.now()
  }

  // Tracker windows opening and closing, straight from the compositor: that is
  // what switches the cadence, and it costs nothing while nothing happens.
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name === "openwindow") {
        // ADDRESS,WORKSPACENAME,CLASS,TITLE (the title may itself contain commas)
        var parts = String(event.data).split(",")
        if (parts.length >= 3 && root.isTrackerClass(parts[2])) root.noteWindowOpened(parts[0])
      } else if (event.name === "closewindow") {
        root.noteWindowClosed(String(event.data))
      }
    }
  }

  Component.onCompleted: root.refresh()

  Row {
    id: row
    height: parent.height

    WidgetButton {
      id: waveButton
      bar: root.bar
      text: root.glyph
      dimmed: root.sourceState !== "ok" || root.toggling
      horizontalMargin: 7
      tooltipText: root.sourceState !== "ok"
        ? "TrafficFlow: " + root.why
        : (root.running
            ? "Tracking " + root.runningLabel + " — press to pause"
            : "Press to resume today's last timer")
      onPressed: function(b) {
        if (b === Qt.RightButton) root.openApp()
        else if (b === Qt.MiddleButton) root.refresh()
        else root.toggle()
      }
    }

    WidgetButton {
      id: timeButton
      bar: root.bar
      text: root.clock
      horizontalMargin: 6
      tooltipText: root.hmm(root.todaySeconds) + " today — press for the tracker"
      onPressed: function(b) {
        if (b === Qt.RightButton) root.openApp()
        else if (b === Qt.MiddleButton) root.refresh()
        else root.summon()
      }
    }
  }
}
