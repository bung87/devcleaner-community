import std/[os, strutils, options, times, pathnorm]
import nregex, chronicles
import ./[types, config_parser, task, utils, constants, filesize, user_prefs]

proc getLastAccessedTime(dir: string): string =
  ## Get formatted last accessed time for a directory
  ## Returns user-friendly relative time (e.g., "2 hours ago", "Yesterday", "Jan 15")
  try:
    let statInfo = getFileInfo(dir)
    let lastAccess = statInfo.lastAccessTime
    let now = getTime()
    let diff = now - lastAccess
    
    if diff < initDuration(minutes = 1):
      result = "Just now"
    elif diff < initDuration(hours = 1):
      let mins = diff.inMinutes
      result = (if mins == 1: "1 minute ago" else: $mins & " minutes ago")
    elif diff < initDuration(hours = 24):
      let hrs = diff.inHours
      result = (if hrs == 1: "1 hour ago" else: $hrs & " hours ago")
    elif diff < initDuration(days = 2):
      result = "Yesterday"
    elif diff < initDuration(days = 7):
      result = $diff.inDays & " days ago"
    elif diff < initDuration(days = 30):
      let weeks = diff.inDays div 7
      result = (if weeks == 1: "1 week ago" else: $weeks & " weeks ago")
    elif diff < initDuration(days = 365):
      # Format as "Jan 15" or "Mar 3"
      result = lastAccess.format("MMM d")
    else:
      # Format as "Jan 15, 2023"
      result = lastAccess.format("MMM d, yyyy")
  except CatchableError:
    result = "Unknown"


# Thread-local scan timing tracking
type
  ScanTiming = ref object
    startTime: Time
    endTime: Time
    durationMs: float

proc startTiming(): ScanTiming =
  result = ScanTiming()
  result.startTime = getTime()

proc stopTiming(t: ScanTiming) =
  t.endTime = getTime()
  t.durationMs = (t.endTime - t.startTime).inMilliseconds.float

proc hasMarkers*(dir: string, markers: seq[string]): bool =
  ## Check if directory contains any of the specified markers
  ## Supports glob patterns like *.nimble using walkPattern

  for marker in markers:
    # Check for glob pattern
    if "*" in marker or "?" in marker:
      # Use walkPattern to find matching files
      let pattern = dir / marker
      for path in walkPattern(pattern):
        if fileExists(path) or dirExists(path):
          return true
    else:
      # Exact match
      let fullMarker = dir / marker
      if fileExists(fullMarker) or dirExists(fullMarker):
        return true


proc findRecursiveTargets(
  dir: string,
  config: SearchConfig,
  onFound: proc(dir: string) {.gcsafe.}
) =
  ## Find recursive targets and call onFound for each match immediately
  ## Requires both markers and targets to be configured
  assert config.recursiveMarkers.len > 0, "recursive search requires markers to be configured"
  assert config.recursiveTargets.len > 0, "recursive search requires targets to be configured"

  var stack: seq[tuple[path: string, level: int]] = @[(dir, 0)]

  while stack.len > 0:
    let (currentPath, currentLevel) = stack.pop()
    let baseName = extractFilename(currentPath)

    if normalizePath(expandTilde(currentPath)) in config.skipDirs:
      continue

    # Check if we should skip hidden directories
    if config.recursiveSkipHidden and baseName.startswith("."):
      # Allow specific hidden directories if configured
      if baseName notin config.recursiveAllowHidden:
        continue

    # Check if this directory has markers (indicates a project)
    if hasMarkers(currentPath, config.recursiveMarkers):
      # This is a project directory, check for targets to clean
      for target in config.recursiveTargets:
        if baseName == target:
          onFound(currentPath)
          break
        else:
          let targetPath = currentPath / target
          if dirExists(targetPath):
            onFound(targetPath)
      # Don't traverse into project directories to find nested projects
      continue


    for kind, path in walkDir(currentPath):
      if kind == pcDir:
        let name = extractFilename(path)
        if name.startswith(".") and config.recursiveSkipHidden:
          if name notin config.recursiveAllowHidden:
            continue
        if normalizePath(expandTilde(path)) in config.skipDirs:
          continue
        stack.add((path, currentLevel + 1))


proc findRegexMatches(
  dir: string,
  config: SearchConfig,
  pattern: Regex,
  onFound: proc(dir: string) {.gcsafe.}
) =
  ## Find regex matches and call onFound for each match immediately
  var stack: seq[tuple[path: string, level: int]] = @[(dir, 0)]

  while stack.len > 0:
    let (currentPath, currentLevel) = stack.pop()

    let baseName = extractFilename(currentPath)

    if baseName.startswith("."):
      if baseName notin config.regexSkipHiddenExcept:
        continue

    if normalizePath(expandTilde(currentPath)) in config.skipDirs:
      continue

    var m: RegexMatch
    if nregex.find(currentPath, pattern, m):
      onFound(currentPath)
      continue

    try:
      for kind, path in walkDir(currentPath):
        if kind == pcDir:
          if normalizePath(expandTilde(path)) in config.skipDirs:
            continue
          stack.add((path, currentLevel + 1))
    except CatchableError:
      error "Failed to walk directory", path = currentPath

proc getStaticDirs(config: SearchConfig, onFound: proc(dir: string) {.gcsafe.}) =
  ## Get static directories and call onFound for each match immediately
  for dir in config.staticDirs:
    let expanded = expandTilde(dir)
    if dirExists(expanded):
      onFound(expanded)

type
  ScanContext = ref object
    total: int64
    config: TaskConfig
    searchConfig: SearchConfig
    channel: ptr Channel[Message]

proc processDir(ctx: ScanContext, dir: string) {.gcsafe.} =
  ## Process a found directory - check skip list, calculate size, and send result
  let expandedDir = normalizePath(expandTilde(dir))
  if not dirExists(expandedDir):
    return
  if expandedDir in ctx.searchConfig.skipDirs:
    return

  # Start timing the directory processing
  var timing = startTiming()
  let size = directorySize(expandedDir)
  stopTiming(timing)

  if size > 0:
    ctx.total += size
    let lastAccessed = getLastAccessedTime(expandedDir)
    ctx.channel[].send(Message(
      kind: mkScanResult,
      name: ctx.config.name,
      dir: expandedDir,
      size: size,
      lastAccessed: lastAccessed,
      projectDescription: none(string)
    ))

proc scanProject*(config: TaskConfig, channel: ptr Channel[Message], userFolders: seq[string] = @[]): int64 =
  ## Scan project and send results through channel during scanning
  ## Returns the total size of all found cache directories
  ## If userFolders is provided, uses those instead of config base directory
  result = 0

  if config.search.isNone:
    return

  let searchConfig = config.search.get()

  var ctx = ScanContext(
    total: 0,
    config: config,
    searchConfig: searchConfig,
    channel: channel
  )

  proc onFound(dir: string) {.gcsafe.} =
    processDir(ctx, dir)

  case searchConfig.searchType
  of stStatic:
    # For static scans, use static directories from config
    getStaticDirs(searchConfig, onFound)
  of stRecursive:
    # For recursive scans, use user-provided folders or default base
    var foldersToScan: seq[string] = @[]
    
    if userFolders.len > 0:
      foldersToScan = userFolders
    else:
      foldersToScan = @[expandTilde(searchConfig.base)]
    
    for base in foldersToScan:
      if dirExists(base):
        findRecursiveTargets(base, searchConfig, onFound)
  of stRegex:
    let base = expandTilde(searchConfig.base)
    if dirExists(base) and searchConfig.regexPattern.len > 0:
      try:
        let rePattern = re(searchConfig.regexPattern)
        findRegexMatches(base, searchConfig, rePattern, onFound)
      except CatchableError:
        debug "Invalid regex pattern"

  result = ctx.total


proc scanWorker(arg: ScanWorkerArg) {.thread.} =
  ## Worker thread that receives config via argument tuple
  let resultChannel = arg.chan
  let configName = arg.configName
  let configType = arg.configType
  var total: int64 = 0
  var appName = configName
  var timing = startTiming()

  try:
    let configs = parseConfig(BuiltinConfigContent)
  
    var config: TaskConfig
    var found = false
    for c in configs:
      if c.name == configName and c.configType == configType:
        config = c
        found = true
        break

    assert found, "Config not found: " & configName

    appName = config.name
    if config.search.isSome:
      var searchConfig = config.search.get()
      # Normalize existing skipDirs from config file
      var normalizedSkipDirs: seq[string] = @[]
      for d in searchConfig.skipDirs:
        normalizedSkipDirs.add(normalizePath expandTilde(d))
      searchConfig.skipDirs = normalizedSkipDirs
      # Add SkipDirs from constants
      for d in SkipDirs:
        searchConfig.skipDirs.add(normalizePath expandTilde(d))
      config.search = some(searchConfig)
    
    # Load user-selected folders for recursive scans
    var userFolders: seq[string] = @[]
    if config.search.isSome and config.search.get().searchType == stRecursive:
      let prefs = loadUserPrefs()
      for folder in prefs.selectedFolders:
        let expanded = expandTilde(folder)
        if dirExists(expanded):
          userFolders.add(expanded)
      debug "Using user-selected folders for scan", count = userFolders.len

    total = scanProject(config, resultChannel, userFolders)
    info "Scan completed", app = appName, total = fileSizeHumanReadable(total)
  except CatchableError:
    debug "Scan failed"
  finally:
    stopTiming(timing)
    let duration = (timing.durationMs / 1000.0).float32  # Convert to seconds
    resultChannel[].send(Message(
      kind: mkScanDone,
      name: appName,
      total: total,
      duration: duration
    ))
    sleep(100)

proc scanWithConfig*(task: Task) =
  ## Scan procedure that uses the task's config
  let configName = task.taskConfig.name
  let configType = task.taskConfig.configType

  initChannel(task)
  task.isScanning = true
  task.cache.setLen(0)

  let arg: ScanWorkerArg = (chan: task.channel, configName: configName, configType: configType)
  createThread(task.configThread, scanWorker, arg)

proc staticScanBatchWorker(resultChannel: ptr Channel[Message]) {.thread.} =
  ## Worker thread that scans all static directories sequentially
  ## This prevents multiple TCC permission dialogs from appearing
  let configs = parseConfig(BuiltinConfigContent)
  
  for config in configs:
    if config.search.isNone:
      continue
    let searchConfig = config.search.get()
    if searchConfig.searchType != stStatic:
      continue
    
    let configName = config.name
    var total: int64 = 0
    var timing = startTiming()
    
    try:
      total = scanProject(config, resultChannel)
      info "Scan completed", app = configName, total = fileSizeHumanReadable(total)
    except CatchableError:
      debug "Scan failed", app = configName
    finally:
      stopTiming(timing)
      let duration = (timing.durationMs / 1000.0).float32
      resultChannel[].send(Message(
        kind: mkScanDone,
        name: configName,
        total: total,
        duration: duration
      ))
      sleep(100)

proc scanStaticBatch*(resultChannel: ptr Channel[Message]) =
  ## Scan all static configurations in a single thread
  ## This prevents multiple TCC permission dialogs from appearing
  # Allocate thread on heap so it doesn't go out of scope
  var threadPtr = cast[ptr Thread[ptr Channel[Message]]](alloc0(sizeof(Thread[ptr Channel[Message]])))
  createThread(threadPtr[], staticScanBatchWorker, resultChannel)
  # Note: We don't join the thread here - it runs independently
  # The UI will poll for results through the channel
  # The thread will be cleaned up when the program exits
