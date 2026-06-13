## macOS utilities for DevCleaner
## Provides macOS-specific functionality using Darwin bindings

import std/[os, strutils]
import chronicles
import darwin/objc/runtime
import darwin/[app_kit, foundation]
import darwin/foundation/nsbundle

proc moveToTrash*(path: string): bool =
  ## Move a file or directory to trash using NSFileManager
  ## Returns true if successful, false otherwise
  let fileManager = NSFileManager.defaultManager()
  if fileManager == nil:
    return false

  let url = NSURL.fileURLWithPath(NSString.withUTF8String(path))
  if url == nil:
    return false

  result = fileManager.trashItemAtURL(url)

proc playTrashSound*() =
  ## Play the macOS "Move to Trash" sound effect using NSSound
  ## Note: "Trash" is not a standard NSSound name, use "Pop" as alternative
  let sound = NSSound.soundNamed(@"Pop")
  if sound != nil:
    discard sound.play()

proc playCompletionSound*() =
  ## Play the macOS "Hero" sound effect for scan completion
  ## Hero.aiff is a pleasant success/achievement sound
  let sound = NSSound.soundNamed(@"Hero")
  if sound != nil:
    discard sound.play()

proc hasFullDiskAccess*(): bool =
  ## Check if the app has Full Disk Access permission
  ## On macOS 10.14+, apps need FDA to access certain directories
  ## We detect this by trying to access a protected file
  ## Returns true if access is granted or not needed
  when not defined(macosx):
    debug "FDA Check: Not macOS, returning true"
    return true
  
  # Try to open a file in a protected location
  # Using Safari's directory as a test case
  let testPath = getHomeDir() / "Library" / "Safari" / "Bookmarks.plist"
  debug "FDA Check: Test path", path = testPath
  
  # If the file doesn't exist, try another location
  if not fileExists(testPath):
    debug "FDA Check: Bookmarks.plist not found"
    # Try to list the Safari directory itself
    let safariDir = getHomeDir() / "Library" / "Safari"
    let dirExists = dirExists(safariDir)
    debug "FDA Check: Safari dir status", path = safariDir, exists = dirExists
    if dirExists:
      # Directory exists but we might not have access
      # Try to walk it - this will fail without FDA
      try:
        var count = 0
        for kind, path in walkDir(safariDir):
          count.inc
        debug "FDA Check: Successfully walked Safari dir", entries = count
        return true
      except CatchableError as e:
        debug "FDA Check: Failed to walk Safari dir", error = e.msg
        return false
    else:
      # Safari directory doesn't exist, assume we have access
      # (user might not use Safari)
      debug "FDA Check: Safari dir not found, assuming access granted"
      return true
  
  # Try to open the file - this will fail without FDA
  debug "FDA Check: Trying to open Bookmarks.plist"
  try:
    let f = open(testPath, fmRead)
    f.close()
    debug "FDA Check: Successfully opened Bookmarks.plist"
    return true
  except CatchableError as e:
    debug "FDA Check: Failed to open Bookmarks.plist", error = e.msg
    return false

proc showFullDiskAccessDialog*() =
  ## Show a dialog asking the user to grant Full Disk Access
  ## Uses native NSAlert - safe because this is called BEFORE GLFW window creation
  when not defined(macosx):
    return
  
  let alert = NSAlert.alloc().init()
  if alert == nil:
    return
  
  alert.setMessageText(@"Full Disk Access Required")
  alert.setInformativeText(@"DevCleaner needs Full Disk Access to scan your home directory for development cache files. Please grant access in System Settings > Privacy & Security > Full Disk Access.")
  alert.addButtonWithTitle(@"Open System Settings")
  alert.addButtonWithTitle(@"Cancel")
  
  let response = alert.runModal()
  if response == NSAlertFirstButtonReturn:
    # Open System Settings to Full Disk Access
    let url = NSURL.URLWithString(@"x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
    if url != nil:
      discard NSWorkspace.sharedWorkspace().openURL(url)
  
  alert.release()

proc hasDocumentsAccess*(): bool =
  ## Check if the app has access to Documents folder
  ## Returns true if access is granted
  when not defined(macosx):
    return true
  
  let documentsDir = getHomeDir() / "Documents"
  if not dirExists(documentsDir):
    return true  # If Documents doesn't exist, no need for permission
  
  try:
    # Try to list the directory - this will fail without permission
    for kind, path in walkDir(documentsDir):
      discard
    return true
  except CatchableError:
    return false

proc showDocumentsAccessDialog*(): bool =
  ## Show a dialog asking the user to grant Documents folder access
  ## Returns true if user clicked "Authorize", false if "Cancel"
  ## Note: This now uses AppleScript to avoid runModal conflicts
  when not defined(macosx):
    return true
  
  # Import dialog_utils at the top of the file to use showSimpleMessageDialog
  # For now, return true to continue without blocking
  # TODO: Implement AppleScript version if needed
  return true

proc requestTCCAccess*() =
  ## Request TCC access for Documents folder
  ## Accesses the directory to trigger the system permission dialog
  when not defined(macosx):
    return
  
  let documentsDir = getHomeDir() / "Documents"
  if dirExists(documentsDir):
    try:
      discard getFileInfo(documentsDir)
    except:
      discard

proc preflightDocumentsAccess*() =
  ## Pre-flight check for Documents access
  ## Call this once from main thread before starting scan threads
  ## to avoid multiple TCC prompts
  when defined(macosx):
    let documentsDir = getHomeDir() / "Documents"
    if dirExists(documentsDir):
      try:
        # Try to list directory - this will trigger TCC dialog if needed
        # but only once per app launch
        for kind, path in walkDir(documentsDir):
          discard
      except CatchableError:
        # Access denied - threads will handle this gracefully
        discard

proc getAppPath*(): string =
  ## Get the path to the current application executable
  ## Tries to find the .app bundle and return the executable inside
  when defined(macosx):
    let exePath = getAppFilename()
    # Check if we're inside an .app bundle
    # Path would be like: /path/DevCleaner.app/Contents/MacOS/DevCleaner
    var path = exePath
    # Walk up to find .app
    for i in 0..<5:  # Limit depth
      let parent = parentDir(path)
      if parent == "":
        break
      path = parent
      if path.endsWith(".app"):
        # Found the bundle, now find the executable
        let macosDir = path / "Contents" / "MacOS"
        if dirExists(macosDir):
          for kind, filePath in walkDir(macosDir):
            if kind == pcFile:
              return filePath
        break
    # Fallback to current executable path
    return exePath
  else:
    return getAppFilename()

proc isRunningInBundle*(): bool =
  ## Check if the app is running from a .app bundle using NSBundle API
  ## Returns true if the main bundle is not the system default bundle
  when not defined(macosx):
    return false
  
  let mainBundle = NSBundle.mainBundle()
  let bundlePath = $mainBundle.bundlePath()
  
  # If running from a .app bundle, the path will end with .app
  # If running from command line, the path will be the executable path
  result = bundlePath.contains(".app")
