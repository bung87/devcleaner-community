import std/os
import ./getattrlistbulk

when defined(macosx):
  import ./macos_utils

proc directorySize*(dir: string): int64 =
  result = 0
  if not dirExists(dir):
    return 0

  # Use getattrlistbulk for high-performance bulk metadata retrieval on macOS
  # This reduces syscalls from ~20,000 to ~12 for a directory with 10,000 files
  result = directorySizeBulk(dir)

proc getAppAssetsDir*():string =
  when defined(macosx):
    if isRunningInBundle():
      result = getAppDir() / ".." / "Resources" / "assets"
    else:
      result = getCurrentDir() / "assets"
  elif defined(linux):
    when defined(release):
      if existsEnv("APPDIR"):
        result = getEnv("APPDIR") / "/usr/share/devcleaner/assets/"
      else:
        result = "/usr/share/devcleaner/assets/"
    else:
      result = getCurrentDir() / "assets"
  else:
    result = getCurrentDir() / "assets"
