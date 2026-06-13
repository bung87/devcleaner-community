import std/[times, sets, os, osproc, strutils, options]
import ./[task, disk_info, macos_utils, constants, filesize, scanner, config_parser, types, ui_utils, theme,
    native_toolbar, fonts, readme_summarizer, ui_constants, app_state, ui_widgets, discord_rpc, user_prefs]
import ./dialog_sm
import chronicles
import pixie except Color
import nanovg
import ./glfw_nanovg
import ./rendering
import ./icons
import ./icon_cache

type
  Window* = glfw_nanovg.GNVGWindow

  AppEntry* = ref object
    name*: string
    status*: string
    detected*: bool
    task*: Task
    expanded*: bool
    expandAnim*: float32  # 0.0 = collapsed, 1.0 = expanded, for smooth animation
    fadeOutAnim*: float32 # -999.0 = inactive, -N = delay N seconds, 0.0-1.0 = fading, > 1.0 = done
    duration*: float32    # Scan duration in seconds

  ButtonState* = enum bsNormal, bsHover, bsPressed

  UI* = ref object
    window*: Window
    apps: seq[AppEntry]
    pendingScans: HashSet[string]
    diskInfo: DiskInfo
    scrollOffset: float32
    onScan*, onClean*: proc()
    buttonState: ButtonState
    hoverTrashIndex, hoverArrowIndex: int
    hoverInfoPathIndex, hoverInfoAppIndex: int
    hoverTrashPathIndex, hoverTrashAppIndex: int
    infoDialog*, confirmDialog*: Dialog
    appVersion: string
    fbWidth, fbHeight: int32
    scale: float32
    iconSize: int32
    lastCursorWasHand: bool
    showEmptyState*: bool                    # Show "Nothing found" message in center of list
    staticScanChannel*: ptr Channel[Message] # Shared channel for static scans
                                             # Full Disk Access monitoring
    fdaCheckInterval: float32                # Seconds between FDA checks
    lastFDACheckTime: float64                # Last time we checked FDA status
    fdaInitiallyGranted: bool                # Whether FDA was granted at app startup
    fdaCheckCount: int                       # Number of checks performed

# Helper template to access current app state
template appState(ui: UI): AppState = getAppState()

# Dialog input types
type
  DialogInputResult* = enum dirNone, dirHoverBtn, dirClickBtn, dirClickOut
  DialogBounds* = object
    x*, y*, w*, h*: float32

proc handleInput*(d: var Dialog, mx, my: float32, mouseReleased: bool, bounds: DialogBounds): DialogInputResult =
  ## Handle dialog input - update hover state and return interaction result
  ## Only process input when dialog is fully visible (not during animations)
  if not d.isInteractive():
    return dirNone

  # Update hover state for buttons
  let pb = d.primaryBtn
  d.hoverPrimary = mx >= pb.x and mx <= pb.x + pb.w and my >= pb.y and my <= pb.y + pb.h

  if d.hasSecondary:
    let sb = d.secondaryBtn
    d.hoverSecondary = mx >= sb.x and mx <= sb.x + sb.w and my >= sb.y and my <= sb.y + sb.h
  else:
    d.hoverSecondary = false

  let overBtn = d.hoverPrimary or d.hoverSecondary

  if mouseReleased:
    if overBtn:
      if d.hoverPrimary:
        discard d.confirm() # Use state machine confirm
        return dirClickBtn
      else:
        discard d.cancel() # Secondary button cancels
        return dirClickBtn

    # Check if clicked outside dialog
    let overDialog = mx >= bounds.x and mx <= bounds.x + bounds.w and my >= bounds.y and my <= bounds.y + bounds.h
    if not overDialog:
      discard d.cancel()
      return dirClickOut

  if overBtn:
    return dirHoverBtn

  return dirNone

# Forward declarations
proc draw*(ui: UI)
proc updateAnimations(ui: UI)
proc initTasks(ui: UI)
proc scanAll*(ui: UI)
proc cleanAll*(ui: UI)

proc initTasks(ui: UI) =
  ## Initialize tasks from pre-parsed builtin configs
  let builtinConfigs = parseConfig(BuiltinConfigContent)

  for config in builtinConfigs:
    if not shouldShowDirective(config):
      continue

    let task = newTask(config)
    task.scanProc = scanWithConfig

    task.onTaskData = proc(data: TaskData) =
      for i, app in ui.apps:
        if app.name == data.name:
          ui.apps[i].status = data.info
          break

    task.onTaskState = proc(state: TaskState) =
      case state.taskType
      of ttScan:
        if state.status == tsDone:
          debug "Scan completed", app = state.name, total = state.total
          var needFadeOut: seq[int] = @[] # Collect indices of apps to fade out
          for i, app in ui.apps:
            if app.name == state.name:
              ui.apps[i].duration = state.duration
              if state.total == 0:
                debug "No items found", app = state.name
                ui.apps[i].status = "Nothing found"
                needFadeOut.add(i)
              else:
                debug "Items found", app = state.name, size = fileSizeHumanReadable(state.total)
                ui.apps[i].status = fileSizeHumanReadable(state.total)
                # Update Discord status with current app info
                updateDiscordStatus(scanning = true, totalSize = state.total, itemCount = ui.apps[i].task.cache.len,
                    appName = state.name)
              break

          # Assign sequential delays: each item starts after previous one finishes
          for j, idx in needFadeOut:
            ui.apps[idx].fadeOutAnim = -FadeAnimationDuration * j.float32

          ui.diskInfo = getDiskSpaceInfo()

          # Remove from pending scans and update button if all done
          ui.pendingScans.excl(state.name)
          if ui.pendingScans.len == 0 and ui.appState == asScanning:
            # Check if any recursive scans are still running
            var hasRunningScans = false
            for app in ui.apps:
              if app.task != nil and app.task.isScanning:
                hasRunningScans = true
                break

            if not hasRunningScans:
              setAppState(asClean)
              var allEmpty = true
              var totalSize: int64 = 0
              var totalItems: int = 0
              for app in ui.apps:
                if app.status != "Nothing found":
                  allEmpty = false
                if app.task != nil:
                  totalItems += app.task.cache.len
                  for item in app.task.cache:
                    totalSize += item.size
              ui.showEmptyState = allEmpty
              # Update Discord status with final results
              updateDiscordStatus(scanning = false, totalSize = totalSize, itemCount = totalItems)
      of ttClean:
        if state.status == tsDone:
          debug "Clean completed", app = state.name, total = state.total
          for i, app in ui.apps:
            if app.name == state.name:
              ui.apps[i].status = "cleaned"
              # Clear the cache so trash icon disappears
              if ui.apps[i].task != nil:
                ui.apps[i].task.cache.setLen(0)
              # Collapse the app entry
              ui.apps[i].expanded = false
              ui.apps[i].expandAnim = 0.0
              break
          ui.diskInfo = getDiskSpaceInfo()
          # Update Discord status with cleaned size
          updateDiscordStatus(cleaning = true, cleanedSize = state.total, appName = state.name)

    ui.apps.add(AppEntry(name: config.name, status: "", detected: true, task: task, expanded: false, expandAnim: 0.0,
        fadeOutAnim: FadeInactiveValue, duration: 0.0))

# Global UI reference for macOS native toolbar callbacks
when defined(macosx):
  var gUIInstance: UI = nil

  proc toolbarScanCallback() {.cdecl.} =
    if gUIInstance != nil and getAppState() == asScan:
      gUIInstance.showEmptyState = false # Clear empty state message
      gUIInstance.scanAll()

  proc toolbarCleanCallback() {.cdecl.} =
    let state = getAppState()
    debug "Toolbar clean callback triggered", appState = state
    assert gUIInstance != nil, "gUIInstance should not be nil during toolbar callback"
    if state != asClean:
      debug "Clean callback ignored - not in clean state", state = state
      return

    # Calculate total size to clean
    var totalSize: int64 = 0
    var totalItems = 0
    for app in gUIInstance.apps:
      if app.detected and app.task != nil:
        for item in app.task.cache:
          totalSize += item.size
          totalItems += 1

    debug "Total size to clean", totalSize = totalSize
    if totalSize == 0:
      debug "No items to clean"
      return

    # Show custom confirmation dialog
    let totalSizeStr = fileSizeHumanReadable(totalSize)
    debug "Showing clean confirmation dialog", size = totalSizeStr
    gUIInstance.confirmDialog.title = "Clean All"
    gUIInstance.confirmDialog.message = $totalItems & " items (" & totalSizeStr & ")"
    gUIInstance.confirmDialog.itemPath = "" # Empty indicates full clean
    gUIInstance.confirmDialog.itemSize = totalSize
    gUIInstance.confirmDialog.appIndex = -1 # -1 indicates all apps
    gUIInstance.confirmDialog.pathIndex = -1 # -1 indicates full clean
    gUIInstance.confirmDialog.showDialog()
    gUIInstance.window.mouseReleased = false # Consume event

  proc toolbarDiscordToggleCallback(enabled: bool) {.cdecl.} =
    setDiscordEnabled(enabled)
    saveDiscordEnabled(enabled)
    info "Discord Rich Presence", status = (if enabled: "enabled" else: "disabled")

proc handleStaticScanMessage*(ui: UI, msg: Message) =
  ## Handle messages from the static scan batch worker
  case msg.kind
  of mkCleanStart:
    # Internal signal, ignore
    discard
  of mkScanDone:
    debug "Static scan completed", app = msg.name, total = msg.total
    var needFadeOut: seq[int] = @[]
    for i, app in ui.apps:
      if app.name == msg.name:
        ui.apps[i].duration = msg.duration
        ui.apps[i].task.isScanning = false
        if msg.total == 0:
          ui.apps[i].status = "Nothing found"
          needFadeOut.add(i)
        else:
          ui.apps[i].status = fileSizeHumanReadable(msg.total)
          # Update Discord status with current app info
          updateDiscordStatus(scanning = true, totalSize = msg.total, itemCount = ui.apps[i].task.cache.len,
              appName = msg.name)
        break

    # Assign sequential delays for fade out
    for j, idx in needFadeOut:
      ui.apps[idx].fadeOutAnim = -FadeAnimationDuration * j.float32

    ui.diskInfo = getDiskSpaceInfo()
    ui.pendingScans.excl(msg.name)
    if ui.pendingScans.len == 0 and ui.appState == asScanning:
      # Check if any recursive scans are still running
      var hasRunningScans = false
      for app in ui.apps:
        if app.task != nil and app.task.isScanning:
          hasRunningScans = true
          break

      if not hasRunningScans:
        setAppState(asClean)
        var allEmpty = true
        var totalSize: int64 = 0
        var totalItems: int = 0
        for app in ui.apps:
          if app.status != "Nothing found":
            allEmpty = false
          if app.task != nil:
            totalItems += app.task.cache.len
            for item in app.task.cache:
              totalSize += item.size
        ui.showEmptyState = allEmpty
        # Update Discord status with results
        updateDiscordStatus(scanning = false, totalSize = totalSize, itemCount = totalItems)
  of mkScanResult:
    # Add file to the appropriate task's cache
    for i, app in ui.apps:
      if app.name == msg.name and app.task != nil:
        ui.apps[i].task.addCacheEntry(DirInfo(
          name: msg.dir,
          size: msg.size,
          lastAccessed: msg.lastAccessed,
          projectDescription: msg.projectDescription
        ))
        break
  of mkScan:
    discard
  of mkCleanDone:
    # Play trash sound when batch clean completes
    when defined(macosx):
      playTrashSound()

proc newUI*(width, height: int32): UI =
  ## Create a new UI instance with GLFW window and NanoVG context
  result = UI(
    fbWidth: width,
    fbHeight: height,
    scale: 1.0,
    iconSize: BaseIconSize,
    hoverTrashIndex: -1,
    hoverArrowIndex: -1,
    hoverInfoPathIndex: -1,
    hoverInfoAppIndex: -1,
    hoverTrashPathIndex: -1,
    hoverTrashAppIndex: -1,
    appVersion: Version,
    lastCursorWasHand: false,
    fdaCheckInterval: 1.0, # Check every 1 second
    lastFDACheckTime: 0.0,
    fdaInitiallyGranted: false,
    fdaCheckCount: 0
  )

  # Record initial Full Disk Access status
  when defined(macosx) and defined(release):
    result.fdaInitiallyGranted = hasFullDiskAccess()
    if result.fdaInitiallyGranted:
      debug "Full Disk Access already granted at startup"

  # Initialize dialogs
  result.infoDialog.init()
  result.confirmDialog.init()

  # Create window using glfw_nanovg wrapper
  result.window = glfw_nanovg.createWindow(width, height, AppName, resizable = true)
  result.window.setupCallbacks()

  # Setup native macOS toolbar
  when defined(macosx):
    gUIInstance = result
    let nativeHandle = result.window.getNativeHandle()
    assert nativeHandle != nil, "Failed to get native window handle for toolbar"
    var discordEnabled = false
    try:
      discordEnabled = isDiscordEnabled()
    except CatchableError as e:
      warn "Failed to get Discord enabled state, using default (disabled)", error = e.msg
      discordEnabled = false
    setupNativeToolbar(nativeHandle, cast[pointer](toolbarScanCallback), cast[pointer](toolbarCleanCallback), cast[
        pointer](toolbarDiscordToggleCallback), discordEnabled)
    debug "Native toolbar setup complete"

  # Initialize tasks
  result.initTasks()

  # Initialize disk info (no scan needed)
  result.diskInfo = getDiskSpaceInfo()

  # Initialize icon cache for GPU performance
  initIconCache(result.window.vg)

  # Update native toolbar disk info labels after UI initialization
  when defined(macosx):
    updateDiskInfoLabels()

  debug "UI initialized"

proc destroyUI*(ui: UI) =
  ## Clean up UI resources
  # Disconnect Discord RPC
  disconnectDiscord()

  # Clean up icon cache
  cleanupIconCache(ui.window.vg)

  # Close static scan channel if open
  if ui.staticScanChannel != nil:
    ui.staticScanChannel[].close()
    dealloc(ui.staticScanChannel)
    ui.staticScanChannel = nil

  for app in ui.apps:
    if app.task != nil:
      app.task.closeChannel()

  if ui.window != nil:
    ui.window.destroy()

template theme(ui: UI): ThemeColors = getCurrentTheme()

proc updateAnimations(ui: UI) =
  ## Update all animations (fade-out and expand/collapse)
  const frameTime = 1.0 / 60.0
  var i = 0
  while i < ui.apps.len:
    # Update fade-out animation
    let fadeAnim = ui.apps[i].fadeOutAnim
    if fadeAnim < InactiveFadeThreshold:
      discard
    elif fadeAnim < 0.0:
      ui.apps[i].fadeOutAnim += frameTime
      if ui.apps[i].fadeOutAnim >= 0.0:
        ui.apps[i].fadeOutAnim = 0.0
    elif fadeAnim >= 0.0 and fadeAnim < 1.0:
      ui.apps[i].fadeOutAnim += FadeAnimationStep
      if ui.apps[i].fadeOutAnim >= 1.0:
        ui.apps.delete(i)
        continue

    # Update expand/collapse animation
    let targetExpand = if ui.apps[i].expanded: 1.0 else: 0.0
    if ui.apps[i].expandAnim < targetExpand:
      ui.apps[i].expandAnim += ExpandAnimationSpeed
      if ui.apps[i].expandAnim > targetExpand:
        ui.apps[i].expandAnim = targetExpand
    elif ui.apps[i].expandAnim > targetExpand:
      ui.apps[i].expandAnim -= ExpandAnimationSpeed
      if ui.apps[i].expandAnim < targetExpand:
        ui.apps[i].expandAnim = targetExpand

    i += 1

proc drawAppList(ui: UI) =
  ## Draw the application list using NanoVG
  let win = ui.window
  let w = ui.fbWidth.float32
  let h = ui.fbHeight.float32
  let s = ui.scale
  when defined(macosx):
    let startY = WindowPaddingMacOS * s
  else:
    let startY = WindowPaddingOther * s
  let itemHeight = ListItemHeight * s
  let margin = WindowMargin * s
  let containerWidth = w - margin * 2
  let containerHeight = h - startY - margin

  # Draw list background
  drawRoundedRect(win.vg, margin, startY, containerWidth, containerHeight, ListCornerRadius * s,
      ui.theme.listBackground)

  # Draw list header
  let headerHeight = ListHeaderHeight * s
  let headerY = startY + headerHeight / 2 + ListHeaderTextOffset * s

  # Draw header text
  drawText(win.vg, margin + AppColumnX * s, headerY, "App", HeaderFontSize * s, ui.theme.subtitle, getDefaultFont(fwBold))
  drawText(win.vg, margin + StatusColumnX * s, headerY, "Status", HeaderFontSize * s, ui.theme.subtitle, getDefaultFont(fwBold))
  let durationHeaderWidth = measureText(win.vg, "Duration", HeaderFontSize * s, getDefaultFont(fwBold))
  let durationHeaderX = w - margin - DurationColumnRightOffset * s - durationHeaderWidth
  drawText(win.vg, durationHeaderX, headerY, "Duration", HeaderFontSize * s, ui.theme.subtitle, getDefaultFont(fwBold))

  # Draw underline
  drawLine(win.vg, margin + ListSeparatorPadding * s, startY + headerHeight + ListContentPadding * s,
           w - margin - ListSeparatorPadding * s, startY + headerHeight + ListContentPadding * s, s, ui.theme.separator)

  # Calculate total content height for scrolling
  var totalContentHeight = 0.0
  for app in ui.apps:
    if app.fadeOutAnim >= 1.0:
      continue
    let fadeScale = if app.fadeOutAnim < InactiveFadeThreshold or app.fadeOutAnim < 0.0:
      1.0
    else:
      let t = 1.0 - app.fadeOutAnim
      t * t
    let currentItemHeight = itemHeight * fadeScale
    if currentItemHeight >= 1.0:
      totalContentHeight += currentItemHeight
      if app.expanded and app.task != nil and app.task.cache.len > 0:
        let expandedItemHeight = ExpandedItemHeight * s
        totalContentHeight += app.task.cache.len.float32 * expandedItemHeight + ListContentPadding * s

  # Calculate visible content area (below header)
  let listContentStart = startY + headerHeight + ListContentPadding * s
  let listContentHeight = containerHeight - headerHeight - ListContentBottomPadding * s

  # Clamp scroll offset
  let maxScroll = max(0.0, totalContentHeight - listContentHeight)
  ui.scrollOffset = clamp(ui.scrollOffset, 0.0, maxScroll)

  # Set up scissor for list content area (clip items outside visible area)
  win.vg.save()
  win.vg.scissor(margin, listContentStart, containerWidth, listContentHeight)

  # Draw list items with scroll offset
  var currentY = listContentStart - ui.scrollOffset

  # Pre-compute font for Latin-only text (duration strings like "1.5s")
  let latinFont = getDefaultFont()

  for i, app in ui.apps:
    # Skip rendering if fully faded out
    if app.fadeOutAnim >= 1.0:
      continue

    let fadeScale = if app.fadeOutAnim < InactiveFadeThreshold or app.fadeOutAnim < 0.0:
      1.0
    else:
      let t = 1.0 - app.fadeOutAnim
      t * t

    let currentItemHeight = itemHeight * fadeScale
    if currentItemHeight < 1.0:
      continue

    var fullExpandedHeight = 0.0
    var expandedHeight = 0.0
    if app.expanded and app.task != nil and app.task.cache.len > 0:
      let expandedItemHeight = ExpandedItemHeight * s
      fullExpandedHeight = app.task.cache.len.float32 * expandedItemHeight + ListContentPadding * s
      expandedHeight = fullExpandedHeight * app.expandAnim

    # Skip if item is completely outside visible area (using full height for culling)
    # This ensures we don't skip items where only the expanded content is visible
    let totalItemHeight = currentItemHeight + fullExpandedHeight
    if currentY + totalItemHeight < listContentStart or currentY > listContentStart + listContentHeight:
      currentY += currentItemHeight + fullExpandedHeight
      continue

    if i mod 2 == 0:
      drawRect(win.vg, margin, currentY, containerWidth, currentItemHeight, ui.theme.rowBackgroundAlt)

    drawTextWithEmoji(win.vg, margin + AppColumnX * s, currentY + currentItemHeight / 2, app.name, AppNameFontSize * s,
        ui.theme.textPrimary, getDefaultFont())

    let statusX = margin + StatusColumnX * s
    let statusY = currentY + currentItemHeight / 2

    if app.task != nil and app.task.isScanning:
      drawTextWithEmoji(win.vg, statusX, statusY, "scanning...", StatusFontSize * s, ui.theme.textPrimary,
          getDefaultFont())
      let spinnerX = statusX + 70.0 * s
      let spinnerY = statusY - 6.0 * s
      let progress = (epochTime() mod 1.0).float32
      drawSpinner(win.vg, spinnerX, spinnerY, SpinnerSize * s, progress, ui.theme.accent)
    elif app.status == "Nothing found":
      drawText(win.vg, statusX, statusY, app.status, StatusFontSize * s, ui.theme.textPrimary, getDefaultFont())
      if app.duration > 0:
        let durationStr = formatFloat(app.duration, ffDecimal, 1) & "s"
        let durationWidth = measureText(win.vg, durationStr, StatusFontSize * s, latinFont)
        let durationX = w - margin - DurationColumnRightOffset * s - durationWidth
        drawText(win.vg, durationX, statusY, durationStr, StatusFontSize * s, ui.theme.textMuted, latinFont)
    elif app.status.len > 0 and app.task != nil and app.task.cache.len > 0:
      var totalSize: int64 = 0
      for entry in app.task.cache:
        totalSize += entry.size
      let sizeText = fileSizeHumanReadable(totalSize)
      drawText(win.vg, statusX, statusY, sizeText, StatusFontSize * s, ui.theme.textPrimary, getDefaultFont())
      if app.duration > 0:
        let durationStr = formatFloat(app.duration, ffDecimal, 1) & "s"
        let durationWidth = measureText(win.vg, durationStr, StatusFontSize * s, latinFont)
        let durationX = w - margin - DurationColumnRightOffset * s - durationWidth
        drawText(win.vg, durationX, statusY, durationStr, StatusFontSize * s, ui.theme.textMuted, latinFont)

      let iconY = currentY + currentItemHeight / 2 - IconYOffset * s
      let trashX = w - margin - 60.0 * s
      let chevronX = w - margin - 30.0 * s

      let isTrashHovered = ui.hoverTrashIndex == i
      let isChevronHovered = ui.hoverArrowIndex == i

      if app.task != nil and app.task.cache.len > 0:
        drawCachedIcon(win.vg, ikTrash, trashX, iconY, TrashIconSize * s, isTrashHovered)

      let chevronAngle = app.expandAnim * 90.0
      win.vg.save()
      win.vg.translate(chevronX + IconYOffset * s, iconY + IconYOffset * s)
      win.vg.rotate(chevronAngle * 3.14159 / 180.0)
      drawCachedIcon(win.vg, ikChevronRight, -IconYOffset * s, -IconYOffset * s, ChevronIconSize * s, isChevronHovered)
      win.vg.restore()

      if app.expandAnim > 0.0 and app.task.cache.len > 0:
        let expandedY = currentY + currentItemHeight
        let expandedItemHeight = ExpandedItemHeight * s
        let detailFontSize = DetailFontSize * s
        let pathStartX = margin + ExpandedPathIndent * s
        let sizePadding = ExpandedSizePadding * s

        let totalExpandedHeight = (app.task.cache.len.float32 * expandedItemHeight + ListContentPadding * s) * app.expandAnim

        # Calculate max path width for layout
        var maxPathWidth: float32 = 0.0
        for entry in app.task.cache:
          var displayPath = entry.name
          if displayPath.len > 50:
            displayPath = "..." & displayPath[^47..^1]
          let pathWidth = measureTextWithEmoji(win.vg, displayPath, detailFontSize, getDefaultFont())
          if pathWidth > maxPathWidth:
            maxPathWidth = pathWidth

        let sizeColumnX = pathStartX + maxPathWidth + sizePadding
        let lastAccessedColumnX = sizeColumnX + ExpandedSizeColumnWidth * s

        let sepColor = ui.theme.separator.withAlpha(app.expandAnim)
        drawLine(win.vg, margin + ExpandedSeparatorPadding * s, expandedY, w - margin - ExpandedSeparatorPadding * s,
            expandedY, s, sepColor)

        # Clip the expanded content area for smooth animation
        # Ensure scissor doesn't overflow above listContentStart
        let scissorY = max(expandedY, listContentStart)
        let scissorHeight = max(0.0, totalExpandedHeight - (scissorY - expandedY))
        win.vg.save()
        win.vg.scissor(margin, scissorY, containerWidth, scissorHeight)

        var detailY = expandedY + ExpandedItemPadding * s
        for j in 0 ..< app.task.cache.len:
          let rowProgress = min(1.0, max(0.0, (app.expandAnim * app.task.cache.len.float32 - j.float32)))
          if rowProgress <= 0.0:
            break

          let textColor = ui.theme.textSecondary.withAlpha(rowProgress)
          let mutedColor = ui.theme.textMuted.withAlpha(rowProgress)

          let entry = app.task.cache[j]

          # Truncate path if too long
          var displayPath = entry.name
          if displayPath.len > 50:
            displayPath = "..." & displayPath[^47..^1]

          drawTextWithEmoji(win.vg, pathStartX, detailY + expandedItemHeight / 2, displayPath, detailFontSize,
              textColor, getDefaultFont())
          drawText(win.vg, sizeColumnX, detailY + expandedItemHeight / 2, fileSizeHumanReadable(entry.size),
              detailFontSize, mutedColor, latinFont)
          drawText(win.vg, lastAccessedColumnX, detailY + expandedItemHeight / 2, entry.lastAccessed, detailFontSize,
              mutedColor, latinFont)

          let iconY = detailY + expandedItemHeight / 2 - DetailIconYOffset * s
          let trashX = w - margin - 60.0 * s
          let infoX = w - margin - 30.0 * s

          let isDetailTrashHovered = ui.hoverTrashAppIndex == i and ui.hoverTrashPathIndex == j
          let isDetailInfoHovered = ui.hoverInfoAppIndex == i and ui.hoverInfoPathIndex == j

          drawCachedIcon(win.vg, ikTrashSmall, trashX, iconY, DetailTrashIconSize * s, isDetailTrashHovered, rowProgress)
          drawCachedIcon(win.vg, ikInfo, infoX, iconY, DetailInfoIconSize * s, isDetailInfoHovered, rowProgress)

          detailY += expandedItemHeight

        win.vg.restore()
    elif app.status.len > 0:
      drawText(win.vg, statusX, statusY + 3.0 * s, app.status, 12.0 * s, ui.theme.textMuted, getDefaultFont())

    if i < ui.apps.len - 1 and app.fadeOutAnim < 1.0:
      let separatorY = currentY + currentItemHeight - s
      drawLine(win.vg, margin + ListSeparatorPadding * s, separatorY, w - margin - ListSeparatorPadding * s, separatorY,
          ListSeparatorLineWidth * s, ui.theme.separator)

    currentY += currentItemHeight + fullExpandedHeight

  # Restore scissor
  win.vg.restore()

  # Draw "Nothing found" message in center of list when all apps have no results
  if ui.showEmptyState:
    let emptyText = "Nothing found"
    let emptyFont = getDefaultFont()
    let textSize = 16.0 * s
    let textWidth = measureText(win.vg, emptyText, textSize, emptyFont)
    let textX = (w - textWidth) / 2
    let textY = listContentStart + listContentHeight / 2
    drawText(win.vg, textX, textY, emptyText, textSize, ui.theme.textMuted, emptyFont)

  if totalContentHeight > listContentHeight:
    let scrollbarWidth = ScrollbarWidth * s
    let scrollbarX = w - margin - scrollbarWidth
    let scrollbarHeight = listContentHeight * (listContentHeight / totalContentHeight)
    let maxScrollbarY = listContentHeight - scrollbarHeight
    let scrollbarY = listContentStart + (ui.scrollOffset / maxScroll) * maxScrollbarY

    drawRoundedRect(win.vg, scrollbarX - s, listContentStart, scrollbarWidth + 2.0 * s, listContentHeight, scrollbarWidth / 2,
                    ui.theme.separator.withAlpha(ScrollbarTrackAlpha))

    drawRoundedRect(win.vg, scrollbarX, scrollbarY, scrollbarWidth, scrollbarHeight, scrollbarWidth / 2,
                    ui.theme.textMuted.withAlpha(ScrollbarThumbAlpha))


proc drawInfoDialog(ui: UI) =
  let s = ui.scale
  let w = ui.fbWidth.float32
  let dialogW = min(InfoDialogWidth * s, w - InfoDialogMinMargin * s)

  let (shouldDraw, anim) = ui.infoDialog.update(InfoDialogAnimSpeed)
  if not shouldDraw:
    return

  proc drawContent(vg: nanovg.NVGContext, x, y, w, h, alpha, scale: float32) =
    var displayPath = ui.infoDialog.projectPath
    let maxPathWidth = w
    let pathFont = getDefaultFont()
    let pathWidth = measureTextWithEmoji(vg, displayPath, InfoDialogPathFontSize * scale, pathFont)
    if pathWidth > maxPathWidth:
      let avgCharWidth = pathWidth / displayPath.len.float32
      let maxChars = (maxPathWidth / avgCharWidth).int - 3
      if maxChars > 10:
        displayPath = "..." & displayPath[^maxChars..^1]
    drawTextWithEmoji(vg, x, y + 16.0 * scale, displayPath, InfoDialogPathFontSize * scale,
        ui.theme.textSecondary.withAlpha(alpha), pathFont)

    let maxDescWidth = w
    var lineY = y + 41.0 * scale
    var lineCount = 0
    for line in ui.infoDialog.description.split("\n"):
      if lineCount >= InfoDialogMaxLines:
        break
      var displayLine = line
      let lineFont = getDefaultFont()
      if measureTextWithEmoji(vg, displayLine, InfoDialogDescFontSize * scale, lineFont) > maxDescWidth:
        while displayLine.len > 0 and measureTextWithEmoji(vg, displayLine & "...", InfoDialogDescFontSize * scale,
            lineFont) > maxDescWidth:
          displayLine = displayLine[0..^2]
        displayLine.add("...")
      drawTextWithEmoji(vg, x, lineY, displayLine, InfoDialogDescFontSize * scale, ui.theme.textPrimary.withAlpha(
          alpha), lineFont)
      lineY += InfoDialogLineHeight * scale
      lineCount += 1

  drawDialog(ui.window.vg, w, ui.fbHeight.float32, s, ui.theme,
    DialogConfig(
      width: dialogW / s,
      height: InfoDialogHeight,
      animSpeed: InfoDialogAnimSpeed,
      title: "Details",
      primaryBtnText: "Close",
      secondaryBtnText: ""
    ),
    anim,
    ui.infoDialog.hoverPrimary, ui.infoDialog.hoverSecondary,
    ui.infoDialog.primaryBtn, ui.infoDialog.secondaryBtn,
    ui.infoDialog.hasSecondary,
    drawContent
  )

proc drawConfirmDialog(ui: UI) =
  let (shouldDraw, anim) = ui.confirmDialog.update(ConfirmDialogAnimSpeed)
  if not shouldDraw:
    return

  proc drawContent(vg: nanovg.NVGContext, x, y, w, h, alpha, scale: float32) =
    var displayMsg = ui.confirmDialog.message
    let msgFont = getDefaultFont()
    let msgWidth = measureTextWithEmoji(vg, displayMsg, ConfirmDialogMsgFontSize * scale, msgFont)
    if msgWidth > w:
      let avgCharWidth = msgWidth / displayMsg.len.float32
      let maxChars = (w / avgCharWidth).int - 3
      if maxChars > 10:
        displayMsg = displayMsg[0..maxChars] & "..."
    drawTextWithEmoji(vg, x, y + ConfirmDialogContentPadding * scale, displayMsg, ConfirmDialogMsgFontSize * scale,
        ui.theme.textSecondary.withAlpha(alpha), msgFont)

    let sizeText = "Size: " & fileSizeHumanReadable(ui.confirmDialog.itemSize)
    drawTextWithEmoji(vg, x, y + ConfirmDialogContentPadding * scale + 20.0 * scale, sizeText,
        ConfirmDialogSizeFontSize * scale, ui.theme.textSecondary.withAlpha(alpha), getDefaultFont())

  let s = ui.scale
  drawDialog(ui.window.vg, ui.fbWidth.float32, ui.fbHeight.float32, s, ui.theme,
    DialogConfig(
      width: ConfirmDialogWidth,
      height: ConfirmDialogHeight,
      animSpeed: ConfirmDialogAnimSpeed,
      title: ui.confirmDialog.title,
      primaryBtnText: "Move to Trash",
      secondaryBtnText: "Cancel"
    ),
    anim,
    ui.confirmDialog.hoverPrimary, ui.confirmDialog.hoverSecondary,
    ui.confirmDialog.primaryBtn, ui.confirmDialog.secondaryBtn,
    ui.confirmDialog.hasSecondary,
    drawContent
  )

proc draw*(ui: UI) =
  ## Main draw function called every frame
  let win = ui.window
  let w = ui.fbWidth.float32
  let h = ui.fbHeight.float32

  # Update window size info
  win.updateSize()

  # Begin NanoVG frame
  win.beginFrame()

  # Clear background with theme color
  let bgColor = ui.theme.background
  win.vg.fillColor(bgColor)
  win.vg.beginPath()
  win.vg.rect(0.0f, 0.0f, w, h)
  win.vg.fill()

  # Draw UI components
  when not defined(macosx):
    ui.drawDiskInfo()
    ui.drawMainButton()
  ui.drawAppList()

  # Draw info dialog on top
  ui.drawInfoDialog()

  # Draw confirmation dialog on top of everything
  ui.drawConfirmDialog()

  # ui.drawAboutDialog()

  # End NanoVG frame
  win.endFrame()

  # Swap buffers
  win.swapBuffers()

proc handleListItemInput(ui: UI, mx, my: float32, s, w, h, margin: float32): bool =
  ## Handle input for list items. Returns true if over any interactive element.
  when defined(macosx):
    let startY = WindowPaddingMacOS * s
  else:
    let startY = WindowPaddingOther * s
  let itemHeight = ListItemHeight * s
  let headerHeight = ListHeaderHeight * s
  let listContentStart = startY + headerHeight + ListContentPadding * s
  let listContentHeight = h - startY - margin - headerHeight - ListContentBottomPadding * s

  let inListArea = mx >= margin and mx <= w - margin and my >= listContentStart and my <= listContentStart + listContentHeight
  var currentY = listContentStart - ui.scrollOffset
  var overAny = false

  for i, app in ui.apps:
    if app.fadeOutAnim >= 1.0:
      continue

    let fadeScale = if app.fadeOutAnim < InactiveFadeThreshold or app.fadeOutAnim < 0.0: 1.0
                    else: (let t = 1.0 - app.fadeOutAnim; t * t)
    var fullExpandedHeight = 0.0
    if app.expanded and app.task != nil and app.task.cache.len > 0:
      let expandedItemHeight = ExpandedItemHeight * s
      fullExpandedHeight = app.task.cache.len.float32 * expandedItemHeight + ListContentPadding * s

    let currentItemHeight = itemHeight * fadeScale
    if currentItemHeight < 1.0:
      currentY += currentItemHeight + fullExpandedHeight
      continue

    let totalItemHeight = currentItemHeight + fullExpandedHeight
    if currentY + totalItemHeight < listContentStart or currentY > listContentStart + listContentHeight:
      currentY += currentItemHeight + fullExpandedHeight
      continue

    if app.task != nil and app.task.cache.len > 0 and inListArea:
      let iconY = currentY + currentItemHeight / 2 - IconYOffset * s
      let trashX = w - margin - 60.0 * s
      let chevronX = w - margin - 30.0 * s

      if mx >= trashX and mx <= trashX + TrashIconSize * s and my >= iconY and my <= iconY + TrashIconSize * s:
        overAny = true
        ui.hoverTrashIndex = i
        if ui.window.mouseReleased:
          var totalSize: int64 = 0
          for entry in app.task.cache:
            totalSize += entry.size
          ui.confirmDialog.title = "Move to Trash"
          ui.confirmDialog.message = app.name & " (" & $app.task.cache.len & " items)"
          ui.confirmDialog.itemPath = ""
          ui.confirmDialog.itemSize = totalSize
          ui.confirmDialog.appIndex = i
          ui.confirmDialog.pathIndex = -1
          ui.confirmDialog.showDialog()
          ui.window.mouseReleased = false
      elif mx >= chevronX and mx <= chevronX + ChevronIconSize * s and my >= iconY and my <= iconY + ChevronIconSize * s:
        overAny = true
        ui.hoverArrowIndex = i
        if ui.window.mouseReleased:
          ui.apps[i].expanded = not ui.apps[i].expanded

    currentY += currentItemHeight

    if app.expanded and app.task != nil and app.task.cache.len > 0:
      let expandedItemHeight = ExpandedItemHeight * s
      let expandedY = currentY

      for j in 0 ..< app.task.cache.len:
        let rowY = expandedY + ExpandedItemPadding * s + j.float32 * expandedItemHeight
        let iconY = rowY + expandedItemHeight / 2 - DetailIconYOffset * s
        let trashX = w - margin - 60.0 * s
        let infoX = w - margin - 30.0 * s

        if mx >= trashX and mx <= trashX + DetailTrashIconSize * s and my >= iconY and my <= iconY +
            DetailTrashIconSize * s:
          overAny = true
          ui.hoverTrashAppIndex = i
          ui.hoverTrashPathIndex = j
          if ui.window.mouseReleased:
            let dirToClean = ui.apps[i].task.cache[j].name
            let sizeCleaned = ui.apps[i].task.cache[j].size
            ui.confirmDialog.title = "Move to Trash"
            ui.confirmDialog.message = extractFilename(dirToClean)
            ui.confirmDialog.itemPath = dirToClean
            ui.confirmDialog.itemSize = sizeCleaned
            ui.confirmDialog.appIndex = i
            ui.confirmDialog.pathIndex = j
            ui.confirmDialog.showDialog()
            ui.window.mouseReleased = false

        elif mx >= infoX and mx <= infoX + DetailInfoIconSize * s and my >= iconY and my <= iconY + DetailInfoIconSize * s:
          overAny = true
          ui.hoverInfoAppIndex = i
          ui.hoverInfoPathIndex = j
          if ui.window.mouseReleased:
            let projectDir = parentDir(app.task.cache[j].name)
            let description = getProjectDescription(projectDir)
            ui.infoDialog.projectPath = app.task.cache[j].name
            ui.infoDialog.description = if description.len > 0: description else: generateFileTree(app.task.cache[j].name)
            ui.infoDialog.showDialog()
            ui.window.mouseReleased = false

      currentY += fullExpandedHeight

  result = overAny

proc handleMainButtonInput(ui: UI, mx, my: float32, s, w: float32): bool =
  ## Handle main scan/clean button. Returns true if over button.
  let btnW = MainButtonWidth * s
  let btnH = MainButtonHeight * s
  let btnX = w / 2 - btnW / 2
  let btnY = MainButtonYOffset * s

  result = mx >= btnX and mx <= btnX + btnW and my >= btnY and my <= btnY + btnH

  if result:
    if ui.window.mouseDown:
      ui.buttonState = bsPressed
    else:
      ui.buttonState = bsHover

    if ui.window.mouseReleased:
      if getAppState() == asScan:
        ui.scanAll()
      elif getAppState() == asClean:
        ui.cleanAll()
  else:
    ui.buttonState = bsNormal

proc resetHoverState(ui: UI) =
  ui.hoverTrashIndex = -1
  ui.hoverArrowIndex = -1
  ui.hoverInfoAppIndex = -1
  ui.hoverInfoPathIndex = -1
  ui.hoverTrashAppIndex = -1
  ui.hoverTrashPathIndex = -1

proc handleTrashConfirm(ui: UI): bool =
  ## Execute trash action from confirm dialog
  ## Returns true if action was successful and dialog should close
  let i = ui.confirmDialog.appIndex
  let j = ui.confirmDialog.pathIndex
  let dirToClean = ui.confirmDialog.itemPath

  if i == -1:
    # Clean all apps
    when defined(macosx):
      playTrashSound()
    ui.cleanAll()
    return true
  elif j == -1:
    # Clean single app
    when defined(macosx):
      playTrashSound()
    if ui.apps[i].task != nil:
      ui.apps[i].task.startCleanAsync()
    else:
      warn "Cannot clean app, no task available", app = ui.apps[i].name
    return true
  else:
    # Delete single cache item
    if moveToTrash(dirToClean):
      when defined(macosx):
        playTrashSound()
      ui.apps[i].task.cache.delete(j)
      # Reset hover state to prevent stale hover indices
      ui.hoverTrashAppIndex = -1
      ui.hoverTrashPathIndex = -1
      ui.hoverInfoAppIndex = -1
      ui.hoverInfoPathIndex = -1
      # Update status if no more items
      if ui.apps[i].task.cache.len == 0:
        ui.apps[i].status = "cleaned"
      return true
    else:
      warn "Failed to move to trash", path = dirToClean
      return false

proc handleInput*(ui: UI) =
  ## Unified input handling - dialogs first (on top), then main UI
  let mx = ui.window.mouseXScaled
  let my = ui.window.mouseYScaled
  let s = ui.scale
  let w = ui.fbWidth.float32
  let h = ui.fbHeight.float32
  let margin = WindowMargin * s

  template setHandCursor() =
    if not ui.lastCursorWasHand:
      ui.window.setCursor(csHand)
      ui.lastCursorWasHand = true

  template setArrowCursor() =
    if ui.lastCursorWasHand:
      ui.window.setCursor(csArrow)
      ui.lastCursorWasHand = false

  # 1. Handle dialogs first (they're on top)
  if ui.infoDialog.isVisible():
    let dialogW = min(InfoDialogWidth * s, w - InfoDialogMinMargin * s)
    let dialogH = InfoDialogHeight * s
    let dialogX = (w - dialogW) / 2
    let dialogY = (h - dialogH) / 2

    case ui.infoDialog.handleInput(mx, my, ui.window.mouseReleased, DialogBounds(x: dialogX, y: dialogY, w: dialogW, h: dialogH))
    of dirHoverBtn: setHandCursor()
    of dirClickBtn:
      # Close button clicked - close the dialog
      ui.infoDialog.close()
      ui.window.mouseReleased = false # Clear input state
      return
    of dirClickOut:
      # Clicked outside - close the dialog
      ui.infoDialog.close()
      return
    of dirNone: setArrowCursor()
    return # Dialog is open, don't process main UI

  elif ui.confirmDialog.isVisible():
    let dialogW = ConfirmDialogWidth * s
    let dialogH = ConfirmDialogHeight * s
    let dialogX = (w - dialogW) / 2
    let dialogY = (h - dialogH) / 2

    let inputResult = ui.confirmDialog.handleInput(mx, my, ui.window.mouseReleased, DialogBounds(x: dialogX, y: dialogY,
        w: dialogW, h: dialogH))

    # Block main UI while dialog is visible (including animations)
    if ui.confirmDialog.state != dsHidden:
      case inputResult
      of dirHoverBtn:
        setHandCursor()
        return # Dialog is visible, don't process main UI
      of dirClickBtn:
        if ui.confirmDialog.clickedPrimary():
          let success = ui.handleTrashConfirm()
          if success:
            # Only close dialog if action was successful
            ui.confirmDialog.state = dsHidden
            ui.confirmDialog.anim = 0.0
            ui.window.mouseReleased = false # Clear input state
          else:
            # Keep dialog open but clear click state
            ui.confirmDialog.clickedPrimary = false
        return
      of dirClickOut: return
      of dirNone:
        setArrowCursor()
        return # Dialog is visible, don't process main UI

  # 2. Handle main UI (no dialog open)
  let overList = ui.handleListItemInput(mx, my, s, w, h, margin)
  let overBtn = ui.handleMainButtonInput(mx, my, s, w)

  if overList or overBtn:
    setHandCursor()
  else:
    ui.resetHoverState()
    setArrowCursor()

proc updateWindowSize(ui: UI) =
  ## Update window dimensions from framebuffer
  let (fbw, fbh) = ui.window.getFramebufferSize()
  ui.fbWidth = fbw.int32
  ui.fbHeight = fbh.int32
  ui.scale = ui.window.pixelRatio

proc checkAndRelaunchIfFDAGranted(ui: UI) =
  ## Check if Full Disk Access was granted and relaunch if so
  ## Only relaunch if FDA was NOT granted at startup but IS granted now
  when defined(macosx) and defined(release):
    let currentTime = cpuTime()
    if currentTime - ui.lastFDACheckTime >= ui.fdaCheckInterval:
      ui.lastFDACheckTime = currentTime
      ui.fdaCheckCount.inc
      # Skip first check (startup delay), then check immediately
      # Only relaunch if FDA was not granted at startup
      if ui.fdaCheckCount > 1 and not ui.fdaInitiallyGranted:
        if hasFullDiskAccess():
          debug "Full Disk Access granted, relaunching app"
          # Relaunch the app
          let appPath = getAppPath()
          discard startProcess(appPath, options = {poParentStreams})
          # Signal to quit
          ui.window.setShouldClose(true)

proc run*(ui: UI, shouldQuit: ptr bool = nil) =
  ## Main event loop
  ## shouldQuit - optional pointer to a flag that can signal the loop to exit
  ##              (used for graceful shutdown on SIGTERM)
  while not ui.window.shouldClose and (shouldQuit == nil or not shouldQuit[]):
    # Use pollEvents for responsive UI updates during animations
    pollEvents()

    # Update window size
    ui.updateWindowSize()

    # Update theme from system (follows dark/light mode changes)
    updateThemeFromSystem()

    # Check for Full Disk Access grant and auto-relaunch
    ui.checkAndRelaunchIfFDAGranted()

    # Handle scroll input (respects system scroll direction setting)
    let (_, scrollDeltaY) = ui.window.getAndClearScrollDelta(ui.scale)
    if scrollDeltaY != 0:
      # scrollDeltaY > 0 means scrolling down (content moves up)
      # scrollDeltaY < 0 means scrolling up (content moves down)
      # This follows the system scroll direction setting (including natural scrolling)
      ui.scrollOffset -= scrollDeltaY * 30.0 # Subtract to match scroll direction

    # Handle all input (dialogs first, then main UI)
    ui.handleInput()

    # Clear input state for next frame
    ui.window.clearInputState()

    # Update animations
    ui.updateAnimations()
    # ui.updateAboutDialogAnimation()

    # Draw frame
    ui.draw()

    # Poll for task progress
    # First check static scan channel if active
    if ui.staticScanChannel != nil:
      while true:
        let recvResult = ui.staticScanChannel[].tryRecv()
        if not recvResult.dataAvailable:
          break
        ui.handleStaticScanMessage(recvResult.msg)

    # Then poll individual task channels
    for app in ui.apps.mitems:
      if app.detected and app.task != nil:
        if app.task.isScanning or app.task.isCleaning:
          discard app.task.pollMessages()

proc scanAll*(ui: UI) =
  ## Start scanning all apps

  # Note: First launch folder selection is now handled in main() before GLFW window creation
  # This avoids conflicts between NSOpenPanel and GLFW's event loop

  # Pre-check Documents access on macOS before starting threads
  # This prevents multiple TCC prompts from different scan threads
  when defined(macosx):
    preflightDocumentsAccess() # Trigger TCC dialog once in main thread

  setAppState(asScanning)
  ui.showEmptyState = false # Clear empty state message

  # Update Discord status
  updateDiscordStatus(scanning = true)

  ui.pendingScans.clear()

  # Separate static scans from recursive scans
  var hasStaticScans = false
  var recursiveTasks: seq[Task] = @[]

  for app in ui.apps.mitems:
    if app.detected and app.task != nil:
      let config = app.task.taskConfig
      if config.search.isSome and config.search.get().searchType == stStatic:
        hasStaticScans = true
        app.status = "scanning..."
        ui.pendingScans.incl(app.name)
        app.task.isScanning = true
        app.task.cache.setLen(0)
      elif config.search.isSome:
        recursiveTasks.add(app.task)

  # Start static scans in a single thread
  if hasStaticScans:
    if ui.staticScanChannel == nil:
      ui.staticScanChannel = cast[ptr Channel[Message]](alloc0(sizeof(Channel[Message])))
      ui.staticScanChannel[].open()
    scanStaticBatch(ui.staticScanChannel)

  # Start recursive scans in their own threads
  for task in recursiveTasks:
    task.scan()

proc cleanAll*(ui: UI) =
  ## Start cleaning all apps
  for app in ui.apps.mitems:
    if app.detected and app.task != nil and app.task.cache.len > 0:
      app.task.startCleanAsync()
  # Reset to scan state after clean
  setAppState(asScan)
  # Reset Discord status to idle
  updateDiscordStatus(scanning = false, totalSize = 0, itemCount = 0)
