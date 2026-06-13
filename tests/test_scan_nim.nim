import std/[unittest, os, options, strutils]
import ../src/[config_loader, types, utils, scanner, constants]


# Helper proc to scan and collect results
proc scanAndCollect(config: TaskConfig): seq[tuple[dir: string, size: int64]] =
  result = @[]
  if config.search.isNone:
    return

  let searchConfig = config.search.get()

  case searchConfig.searchType
  of stStatic:
    for dir in searchConfig.staticDirs:
      let expandedDir = expandTilde(dir)
      if dirExists(expandedDir) and expandedDir notin searchConfig.skipDirs:
        let size = directorySize(expandedDir)
        if size > 0:
          result.add((dir: expandedDir, size: size))
  of stRecursive:
    let base = expandTilde(searchConfig.base)
    if dirExists(base):
      var stack: seq[string] = @[base]
      while stack.len > 0:
        let currentPath = stack.pop()
        let baseName = extractFilename(currentPath)

        if currentPath in searchConfig.skipDirs:
          continue
        if searchConfig.recursiveSkipHidden and baseName.startswith("."):
          if baseName notin searchConfig.recursiveAllowHidden:
            continue

        # Check if this directory has markers (indicates a project)
        # Note: recursive search requires both markers and targets
        if hasMarkers(currentPath, searchConfig.recursiveMarkers):
          # This is a project directory, check for targets to clean
          for target in searchConfig.recursiveTargets:
            let targetPath = currentPath / target
            if dirExists(targetPath):
              let size = directorySize(targetPath)
              if size > 0:
                result.add((dir: targetPath, size: size))
          # Don't traverse into project directories to find nested projects
          continue

        try:
          for kind, path in walkDir(currentPath):
            if kind == pcDir:
              let name = extractFilename(path)
              if searchConfig.recursiveSkipHidden and name.startswith("."):
                if name notin searchConfig.recursiveAllowHidden:
                  continue
              if path in searchConfig.skipDirs:
                continue
              stack.add(path)
        except:
          discard
  of stRegex:
    discard

suite "Nim Config Scan Tests":
  test "Load nim config from builtin":
    let configs = loadConfigFile(ConfigPath)

    var nimConfig: TaskConfig
    var found = false
    for c in configs:
      if c.name == "nim" and c.configType == ctProject:
        nimConfig = c
        found = true
        break

    check found == true
    check nimConfig.name == "nim"
    check nimConfig.configType == ctProject
    check nimConfig.bin == "nimble"
    check nimConfig.search.isSome == true
    echo "Nim search config present: ", nimConfig.search.isSome

  test "Nim config has recursive search configuration":
    let configs = loadConfigFile(ConfigPath)

    var nimConfig: TaskConfig
    for c in configs:
      if c.name == "nim" and c.configType == ctProject:
        nimConfig = c
        break

    check nimConfig.search.isSome == true
    let search = nimConfig.search.get()
    check search.searchType == stRecursive
    check search.base == "~"
    check search.recursiveTargets.len > 0
    check search.recursiveTargets[0] == "nimcache"
    check search.recursiveMarkers.len > 0
    echo "Search type: ", search.searchType
    echo "Recursive target: ", search.recursiveTargets
    echo "Markers: ", search.recursiveMarkers
    echo "Skip hidden: ", search.recursiveSkipHidden

  test "Scan nimcache directories":
    let configs = loadConfigFile(ConfigPath)

    var nimConfig: TaskConfig
    for c in configs:
      if c.name == "nim" and c.configType == ctProject:
        nimConfig = c
        break

    echo "\nScanning for nimcache directories..."
    echo "Base: ", nimConfig.search.get().base
    echo "Target: ", nimConfig.search.get().recursiveTargets

    let results = scanAndCollect(nimConfig)

    echo "\nFound ", results.len, " nimcache directories:"
    var totalSize: int64 = 0
    for r in results:
      echo "  - ", r.dir, ": ", r.size
      totalSize += r.size
    echo "\nTotal size: ", totalSize

  test "Check shouldShowDirective for nim":
    let configs = loadConfigFile(ConfigPath)

    var nimConfig: TaskConfig
    for c in configs:
      if c.name == "nim" and c.configType == ctProject:
        nimConfig = c
        break

    echo "\nNim config:"
    echo "  bin: '", nimConfig.bin, "'"
    echo "  has search: ", nimConfig.search.isSome

    let shouldShow = shouldShowDirective(nimConfig)
    echo "  shouldShowDirective: ", shouldShow

    # Nim has bin and search config, should show
    check shouldShow == true

  test "Nimble config has static search configuration":
    let configs = loadConfigFile(ConfigPath)

    var nimbleConfig: TaskConfig
    for c in configs:
      if c.name == "nimble" and c.configType == ctProject:
        nimbleConfig = c
        break

    check nimbleConfig.search.isSome == true
    let search = nimbleConfig.search.get()
    check search.searchType == stStatic
    check search.staticDirs.len > 0
    echo "Nimble static dirs: ", search.staticDirs

  test "Scan nimble static directories":
    let configs = loadConfigFile(ConfigPath)

    var nimbleConfig: TaskConfig
    for c in configs:
      if c.name == "nimble" and c.configType == ctProject:
        nimbleConfig = c
        break

    echo "\nScanning nimble static directories..."
    echo "Static dirs: ", nimbleConfig.search.get().staticDirs

    let results = scanAndCollect(nimbleConfig)

    echo "\nFound ", results.len, " nimble directories:"
    var totalSize: int64 = 0
    for r in results:
      echo "  - ", r.dir, ": ", r.size
      totalSize += r.size
    echo "\nTotal size: ", totalSize

  test "Choosenim config has static search configuration":
    let configs = loadConfigFile(ConfigPath)

    var choosenimConfig: TaskConfig
    for c in configs:
      if c.name == "choosenim" and c.configType == ctProject:
        choosenimConfig = c
        break

    check choosenimConfig.search.isSome == true
    let search = choosenimConfig.search.get()
    check search.searchType == stStatic
    check search.staticDirs.len > 0
    echo "Choosenim static dirs: ", search.staticDirs

  test "Scan choosenim static directories":
    let configs = loadConfigFile(ConfigPath)

    var choosenimConfig: TaskConfig
    for c in configs:
      if c.name == "choosenim" and c.configType == ctProject:
        choosenimConfig = c
        break

    echo "\nScanning choosenim static directories..."
    echo "Static dirs: ", choosenimConfig.search.get().staticDirs

    let results = scanAndCollect(choosenimConfig)

    echo "\nFound ", results.len, " choosenim directories:"
    var totalSize: int64 = 0
    for r in results:
      echo "  - ", r.dir, ": ", r.size
      totalSize += r.size
    echo "\nTotal size: ", totalSize
