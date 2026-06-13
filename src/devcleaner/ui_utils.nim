import std/[os]
import options
import chronicles
import ./types

proc shouldShowDirective*(config: TaskConfig): bool =
  case config.configType
  of ctSystem:
    # System directives always show
    return true
  of ctProject:
    # Project directives: show if any bin exists (when specified)
    if config.bin.len > 0:
      for b in config.bin:
        if findExe(b).len > 0:
          return true
      debug "No binaries found", bin = config.bin
      return false

    # No bin specified - check search configuration
    if config.search.isSome:
      let searchConfig = config.search.get()

      # For static searches, check if any static directory exists
      if searchConfig.searchType == stStatic:
        for dir in searchConfig.staticDirs:
          let expanded = expandTilde(dir)
          if dirExists(expanded):
            return true
        return false

      # For other search types, check if base directory exists
      let basePath = expandTilde(searchConfig.base)
      return dirExists(basePath)

    return false
