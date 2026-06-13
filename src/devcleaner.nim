import std/os
import std/posix
import chronicles
import devcleaner/[constants, ui, path_env, discord_rpc, user_prefs]
import devcleaner/glfw_nanovg
import devcleaner/macos_utils

var gShouldQuit = false
var gWindow: GNVGWindow = nil

proc handleSignal(sig: cint) {.noconv.} =
  ## Handle SIGTERM and SIGINT for graceful shutdown
  gShouldQuit = true
  info "Received signal, initiating graceful shutdown", signal = sig
  # Signal GLFW to close window (thread-safe way to wake up event loop)
  if gWindow != nil:
    gWindow.setShouldClose(true)

proc getLogDirectory(): string =
  ## Get the log directory (standard location, no Sandbox)
  when defined(macosx):
    result = getHomeDir() / "Library" / "Logs" / AppName
  else:
    result = getHomeDir() / ".devcleaner" / "logs"

proc main() =
  let logDir = getLogDirectory()
  createDir(logDir)
  let logFile = logDir / "devcleaner.log"

  # Try to open log file, but don't crash if Sandbox prevents it
  try:
    if not defaultChroniclesStream.output.open(logFile, fmAppend):
      # Fallback to stderr if file logging fails
      stderr.writeLine("Warning: Could not open log file: " & logFile)
  except CatchableError as e:
    stderr.writeLine("Warning: Could not initialize logging: " & e.msg)

  # Setup PATH before anything else
  setupPath()

  # Check for Full Disk Access on macOS (only when running from app bundle)
  when defined(macosx) and defined(release):
    if isRunningInBundle():
      if not hasFullDiskAccess():
        showFullDiskAccessDialog()
        # Continue anyway - user might grant access later

      # Initialize Discord RPC
  initDiscordRPC()

  # Load Discord preference and apply it (with error handling to ensure UI always loads)
  var discordPref = false
  try:
    discordPref = loadDiscordEnabled()
    setDiscordEnabled(discordPref)
    debug "Discord preference loaded", enabled = discordPref
  except CatchableError as e:
    warn "Failed to load Discord preference, using default"
    debug "Discord preference load error", error = e.msg
    discordPref = false

  # Register signal handlers for graceful shutdown
  discard signal(SIGTERM, handleSignal)
  discard signal(SIGINT, handleSignal)

  # Create UI with GLFW window
  let ui = newUI(800, 600)
  gWindow = ui.window

  # Set up callbacks
  ui.onScan = proc() =
    ui.scanAll()

  ui.onClean = proc() =
    ui.cleanAll()

  # Run main event loop (pass shouldQuit flag for graceful shutdown)
  ui.run(addr gShouldQuit)
  gWindow = nil

  # Clean up
  ui.destroyUI()

  # Shutdown Discord RPC
  shutdownDiscordRPC()

when isMainModule:
  main()
