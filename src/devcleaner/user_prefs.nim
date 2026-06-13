## User preferences manager
## Stores user-selected folders and app settings in a JSON file
## Note: Base scan configuration comes from builtin.scfg, user prefs are supplemental

import std/[os, sequtils, json]
import chronicles
const
  PrefsFileName = "preferences.json"
  PrefsKeySelectedFolders = "selectedFolders"
  PrefsKeyStaticFolders = "staticFolders"
  PrefsKeyFirstLaunch = "firstLaunch"
  PrefsKeyDiscordEnabled = "discordEnabled"

type
  UserPrefs* = ref object
    ## User preferences container
    ## User-selected folders supplement the base config from builtin.scfg
    selectedFolders*: seq[string]  # User-selected folders for recursive scanning
    staticFolders*: seq[string]    # User-defined static folders (supplemental)
    isFirstLaunch*: bool
    discordEnabled*: bool          # Discord Rich Presence enabled state

proc getPrefsPath(): string =
  ## Get the path to the preferences file
  # Use Application Support directory
  let appSupport = getHomeDir() / "Library" / "Application Support" / "DevCleaner"
  createDir(appSupport)
  result = appSupport / PrefsFileName

proc loadUserPrefs*(): UserPrefs =
  ## Load user preferences from JSON file
  result = UserPrefs(
    selectedFolders: @[],
    staticFolders: @[],
    isFirstLaunch: true,
    discordEnabled: false
  )

  let prefsPath = getPrefsPath()

  if not fileExists(prefsPath):
    # First launch - empty preferences, base config comes from builtin.scfg
    result.staticFolders = @[]
    result.isFirstLaunch = true
    result.discordEnabled = false
    info "First launch, using empty preferences (base config from builtin.scfg)"
    return result
  
  try:
    let content = readFile(prefsPath)
    let json = parseJson(content)
    
    # Load first launch flag
    if json.hasKey(PrefsKeyFirstLaunch):
      result.isFirstLaunch = json[PrefsKeyFirstLaunch].getBool()
    else:
      result.isFirstLaunch = false
    
    # Load selected folders
    if json.hasKey(PrefsKeySelectedFolders):
      for item in json[PrefsKeySelectedFolders]:
        let path = item.getStr()
        if path.len > 0:
          result.selectedFolders.add(path)
    
    # Load static folders (user-defined supplemental folders)
    if json.hasKey(PrefsKeyStaticFolders):
      for item in json[PrefsKeyStaticFolders]:
        let path = item.getStr()
        if path.len > 0:
          result.staticFolders.add(path)

    # Load Discord enabled state
    if json.hasKey(PrefsKeyDiscordEnabled):
      result.discordEnabled = json[PrefsKeyDiscordEnabled].getBool()
    else:
      result.discordEnabled = false

    info "User preferences loaded"
    debug "User preferences details",
      selectedFolders = result.selectedFolders.len,
      staticFolders = result.staticFolders.len,
      isFirstLaunch = result.isFirstLaunch,
      discordEnabled = result.discordEnabled

  except CatchableError as e:
    warn "Failed to load preferences, using defaults"
    debug "Preferences load error", error = e.msg
    result.staticFolders = @[]
    result.isFirstLaunch = true
    result.discordEnabled = false

proc savePrefs*(prefs: UserPrefs) =
  ## Save user preferences to JSON file
  let prefsPath = getPrefsPath()
  
  var json = newJObject()
  json[PrefsKeyFirstLaunch] = %prefs.isFirstLaunch
  
  var selectedArr = newJArray()
  for folder in prefs.selectedFolders:
    selectedArr.add(%folder)
  json[PrefsKeySelectedFolders] = selectedArr
  
  var staticArr = newJArray()
  for folder in prefs.staticFolders:
    staticArr.add(%folder)
  json[PrefsKeyStaticFolders] = staticArr

  # Save Discord enabled state
  json[PrefsKeyDiscordEnabled] = %prefs.discordEnabled

  try:
    writeFile(prefsPath, pretty(json))
    debug "Preferences saved", path = prefsPath
  except CatchableError as e:
    warn "Failed to save preferences"
    debug "Preferences save error", error = e.msg

proc saveSelectedFolders*(folders: seq[string]) =
  ## Save user-selected folders to preferences
  var prefs = loadUserPrefs()
  prefs.selectedFolders = folders
  prefs.isFirstLaunch = false
  savePrefs(prefs)
  debug "Selected folders saved", count = folders.len

proc saveStaticFolders*(folders: seq[string]) =
  ## Save static folders to preferences
  var prefs = loadUserPrefs()
  prefs.staticFolders = folders
  savePrefs(prefs)
  debug "Static folders saved", count = folders.len

proc removeSelectedFolder*(path: string) =
  ## Remove a selected folder
  var prefs = loadUserPrefs()
  prefs.selectedFolders = prefs.selectedFolders.filterIt(it != path)
  savePrefs(prefs)
  debug "Folder removed", path = path

proc saveDiscordEnabled*(enabled: bool) =
  ## Save Discord Rich Presence enabled state to preferences
  var prefs = loadUserPrefs()
  prefs.discordEnabled = enabled
  savePrefs(prefs)
  debug "Discord enabled state saved", enabled = enabled

proc loadDiscordEnabled*(): bool =
  ## Load Discord Rich Presence enabled state from preferences
  let prefs = loadUserPrefs()
  result = prefs.discordEnabled
  debug "Discord enabled state loaded", enabled = result

proc resetToDefaults*() =
  ## Reset all preferences to defaults (empty, base config from builtin.scfg)
  var prefs = UserPrefs(
    selectedFolders: @[],
    staticFolders: @[],
    isFirstLaunch: true,
    discordEnabled: false
  )
  savePrefs(prefs)
  info "Preferences reset to defaults"

proc getEffectiveScanFolders*(): seq[string] =
  ## Get all folders that should be scanned
  ## Combines user-selected folders and expands paths
  let prefs = loadUserPrefs()
  
  result = @[]
  
  # Add user-selected folders
  for folder in prefs.selectedFolders:
    let expanded = expandTilde(folder)
    if dirExists(expanded):
      result.add(expanded)

  # Add static folders (cache directories)
  for folder in prefs.staticFolders:
    let expanded = expandTilde(folder)
    if dirExists(expanded):
      result.add(expanded)
  
  # Remove duplicates
  result = result.deduplicate()
