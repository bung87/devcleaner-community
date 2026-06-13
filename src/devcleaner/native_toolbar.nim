## Native NSToolbar integration for macOS
## @TODO: button has no hover effect https://stackoverflow.com/questions/62882972/macos-big-sur-new-toolbar-button-style
#

import darwin/objc/runtime
import darwin/[app_kit, foundation]
import darwin/core_graphics/cggeometry
import ./disk_info
import std/strformat

type
  ToolbarButtonState* = enum
    tbsScan       ## Show "Scan" with magnifyingglass icon
    tbsScanning   ## Show "Scanning..." with progress icon
    tbsClean      ## Show "Clean" with trash icon

var
  gScanCallback: pointer = nil
  gCleanCallback: pointer = nil
  gDiscordToggleCallback: pointer = nil
  gDelegateClass: ObjcClass = nil
  gDelegateInstance: NSObject = nil
  gScanButton: NSButton = nil
  gScanToolbarItem: NSToolbarItem = nil
  gDiscordButton: NSButton = nil
  gDiscordToolbarItem: NSToolbarItem = nil
  gDiskInfoToolbarItem: NSToolbarItem = nil
  gToolbar: NSToolbar = nil
  gTotalLabel: NSTextField = nil
  gFreeLabel: NSTextField = nil
  gDiscordEnabled: bool = false

proc mdcScanActionHandler(self: ID, cmd: SEL, sender: ID) {.cdecl.}
proc mdcCleanActionHandler(self: ID, cmd: SEL, sender: ID) {.cdecl.}
proc mdcDiscordToggleHandler(self: ID, cmd: SEL, sender: ID) {.cdecl.}
proc mdcToolbarDefaultItemIdentifiers(self: ID, cmd: SEL, toolbar: ID): ID {.cdecl.}
proc mdcToolbarAllowedItemIdentifiers(self: ID, cmd: SEL, toolbar: ID): ID {.cdecl.}
proc mdcToolbarItemForItemIdentifier(self: ID, cmd: SEL, toolbar: ID, itemIdentifier: NSString, willBeInsertedIntoToolbar: BOOL): ID {.cdecl.}
proc initToolbarDelegate()


proc setupNativeToolbar*(glfwWindowHandle: pointer, onScan: pointer, onClean: pointer, onDiscordToggle: pointer = nil, initialDiscordState: bool = false) =
  ## Setup native NSToolbar for the GLFW window
  gScanCallback = onScan
  gCleanCallback = onClean
  gDiscordToggleCallback = onDiscordToggle
  gDiscordEnabled = initialDiscordState

  initToolbarDelegate()

  let nsWindow = cast[NSObject](glfwWindowHandle)
  if nsWindow.isNil:
    return

  let toolbar = NSToolbar.alloc()
  discard toolbar.initWithIdentifier(@"DevCleanerToolbar")

  toolbar.setDisplayMode(NSToolbarDisplayModeIconOnly)
  # toolbar.setSizeMode(NSToolbarSizeModeRegular)
  toolbar.setDelegate(gDelegateInstance)
  toolbar.setAutosavesConfiguration(NO)

  gToolbar = toolbar

  type SetToolbarProc = proc(self: NSObject, cmd: SEL, toolbar: NSToolbar) {.cdecl.}
  let setToolbarP = cast[SetToolbarProc](objc_msgSend)
  setToolbarP(nsWindow, selector("setToolbar:"), toolbar)

proc updateToolbarButton*(state: ToolbarButtonState) =
  ## Update the toolbar scan button based on app state
  if gScanButton.isNil:
    return
  
  case state
  of tbsScan:
    let image = NSImage.imageWithSystemSymbolName(@"magnifyingglass", @"magnifyingglass")
    if not image.isNil:
      gScanButton.setImage(image)
    gScanButton.setTitle(@"Scan")
    gScanButton.setAction(selector("mdcScanActionHandler:"))
    if not gScanToolbarItem.isNil:
      gScanToolbarItem.setToolTip(@"Scan for development artifacts")
  of tbsScanning:
    let image = NSImage.imageWithSystemSymbolName(@"rays", @"rays")
    if not image.isNil:
      gScanButton.setImage(image)
    gScanButton.setTitle(@"Scanning...")
    gScanButton.setEnabled(NO)
    return  # Don't re-enable at the end for scanning state
  of tbsClean:
    let image = NSImage.imageWithSystemSymbolName(@"xmark.bin", @"xmark.bin")
    if not image.isNil:
      gScanButton.setImage(image)
    gScanButton.setTitle(@"Clean")
    gScanButton.setAction(selector("mdcCleanActionHandler:"))
    if not gScanToolbarItem.isNil:
      gScanToolbarItem.setToolTip(@"Move selected items to trash")
    gScanButton.setNeedsDisplay(YES)
  
  gScanButton.setEnabled(YES)

proc updateDiskInfoLabels*() =
  ## Update the disk info labels with actual disk space information
  if gTotalLabel.isNil or gFreeLabel.isNil:
    return
  
  let diskInfo = getDiskSpaceInfo()
  let formatted = formatDiskInfo(diskInfo)
  let totalText = &"Total: {formatted.total}"
  let freeText = &"Free: {formatted.free}"
  
  gTotalLabel.setStringValue(@totalText)
  gFreeLabel.setStringValue(@freeText)

proc mdcScanActionHandler(self: ID, cmd: SEL, sender: ID) {.cdecl.} =
  if gScanCallback != nil:
    let cb = cast[proc() {.cdecl.}](gScanCallback)
    cb()

proc mdcCleanActionHandler(self: ID, cmd: SEL, sender: ID) {.cdecl.} =
  if gCleanCallback != nil:
    let cb = cast[proc() {.cdecl.}](gCleanCallback)
    cb()

proc mdcDiscordToggleHandler(self: ID, cmd: SEL, sender: ID) {.cdecl.} =
  gDiscordEnabled = not gDiscordEnabled
  if gDiscordButton != nil:
    let imageName = if gDiscordEnabled: @"gamecontroller.fill" else: @"gamecontroller"
    let image = NSImage.imageWithSystemSymbolName(imageName, imageName)
    if not image.isNil:
      gDiscordButton.setImage(image)
    let tooltip = if gDiscordEnabled: @"Discord Rich Presence: ON" else: @"Discord Rich Presence: OFF"
    if not gDiscordToolbarItem.isNil:
      gDiscordToolbarItem.setToolTip(tooltip)
  if gDiscordToggleCallback != nil:
    let cb = cast[proc(enabled: bool) {.cdecl.}](gDiscordToggleCallback)
    cb(gDiscordEnabled)

proc mdcToolbarDefaultItemIdentifiers(self: ID, cmd: SEL, toolbar: ID): ID {.cdecl.} =
  let arr = mutableArrayWithCapacity[NSString](6)
  arr.add(@"DiskInfo")
  arr.add(@"DiscordButton")
  arr.add(@"NSToolbarFlexibleSpaceItem")  # 第一个弹簧：把 ScanButton 往右推
  arr.add(@"ScanButton")                   # 目标居中项
  arr.add(@"NSToolbarFlexibleSpaceItem")  # 第二个弹簧：把 ScanButton 往左推
  result = cast[ID](arr)

proc mdcToolbarAllowedItemIdentifiers(self: ID, cmd: SEL, toolbar: ID): ID {.cdecl.} =
  let arr = mutableArrayWithCapacity[NSString](6)
  arr.add(@"DiskInfo")
  arr.add(@"DiscordButton")
  arr.add(@"NSToolbarFlexibleSpaceItem")
  arr.add(@"ScanButton")
  arr.add(@"NSToolbarFlexibleSpaceItem")
  result = cast[ID](arr)

proc createScanButton(item: NSToolbarItem): NSButton =
  ## Create the scan/clean button for the toolbar
  let button = NSButton.alloc()
  discard button.initWithFrame(NSMakeRect(0, 0, 80, 32))

  # button.setBezelStyle(0.NSInteger)  # NSBezelStyleAutomatic，让系统自动应用工具栏样式
  # button.setButtonType(NSButtonType.NSButtonType)
  button.setEnabled(YES)
  
  let image = NSImage.imageWithSystemSymbolName(@"magnifyingglass", @"magnifyingglass")
  if not image.isNil:
    button.setImage(image)
  

  # NSImageScaling* {.size: sizeof(uint).} = enum
  #   NSImageScaleProportionallyDown
  #   NSImageScaleAxesIndependently
  #   NSImageScaleNone
  #   NSImageScaleProportionallyUpOrDown
  button.setTitle(@"Scan")
  cast[NSButtonCell](button).setImagePosition(nscell.NSCellImagePosition.NSImageLeading)
  cast[NSButtonCell](button).setImageScaling(nscell.NSImageScaling.NSImageScaleProportionallyDown)
  
  button.setTarget(gDelegateInstance)
  button.setAction(selector("mdcScanActionHandler:"))
  
  gScanButton = button
  gScanToolbarItem = item
  
  item.setView(button)
  item.setToolTip(@"Scan for dependencies and build caches")
  item.setPaletteLabel(@"Scan")
  
  result = button

proc createDiskInfoItem(item: NSToolbarItem) =
  ## Create the disk info display item for the toolbar
  const
    toolbarHeight = 44
    imageSize = 32
    gap = 4
  
  let colorClass = getClass("NSColor")
  let labelColor = objc_msgSend(colorClass, selector("labelColor"))
  
  let imageView = NSImageView.alloc()
  discard imageView.initWithFrame(NSMakeRect(0, 0, imageSize, imageSize))
  
  let diskImage = NSImage.imageWithSystemSymbolName(@"internaldrive", @"DiskInfo")
  if not diskImage.isNil:
    let symbolConfig = NSImageSymbolConfiguration.configurationWithPointSize(CGFloat(28.0), NSImageSymbolWeightUnspecified)
    let configuredImage = diskImage.withSymbolConfiguration(symbolConfig)
    imageView.setImage(configuredImage)
  
  let totalLabel = NSTextField.alloc()
  discard totalLabel.initWithFrame(NSMakeRect(0, 0, 150, 14))
  totalLabel.setStringValue(@"Total: ...")
  totalLabel.setFont(NSFont.systemFontOfSize(11))
  totalLabel.setTextColor(cast[NSColor](labelColor))
  totalLabel.setEditable(NO)
  totalLabel.setBezeled(NO)
  totalLabel.setDrawsBackground(NO)
  
  let freeLabel = NSTextField.alloc()
  discard freeLabel.initWithFrame(NSMakeRect(0, 0, 150, 14))
  freeLabel.setStringValue(@"Free: ...")
  freeLabel.setFont(NSFont.systemFontOfSize(11))
  freeLabel.setTextColor(cast[NSColor](labelColor))
  freeLabel.setEditable(NO)
  freeLabel.setBezeled(NO)
  freeLabel.setDrawsBackground(NO)
  
  gTotalLabel = totalLabel
  gFreeLabel = freeLabel
  
  let labelStack = NSStackView.alloc()
  discard labelStack.initWithFrame(NSMakeRect(0, 0, 150, 30))
  labelStack.setOrientation(NSUserInterfaceLayoutOrientationVertical)
  labelStack.setSpacing(2)
  labelStack.setDistribution(NSStackViewDistributionFillEqually)
  labelStack.addView(totalLabel, NSStackViewGravityLeading)
  labelStack.addView(freeLabel, NSStackViewGravityLeading)
  
  let contentStack = NSStackView.alloc()
  discard contentStack.initWithFrame(NSMakeRect(0, 0, 200, toolbarHeight))
  contentStack.setOrientation(NSUserInterfaceLayoutOrientationHorizontal)
  contentStack.setSpacing(gap)
  contentStack.setDistribution(NSStackViewDistributionFill)
  contentStack.setAlignment(NSLayoutAttributeCenterY)
  contentStack.addView(imageView, NSStackViewGravityLeading)
  contentStack.addView(labelStack, NSStackViewGravityLeading)
  
  item.setView(contentStack)
  item.setPaletteLabel(@"Disk Info")

proc createDiscordButton(item: NSToolbarItem): NSButton =
  ## Create the Discord toggle button for the toolbar
  let button = NSButton.alloc()
  discard button.initWithFrame(NSMakeRect(0, 0, 44, 32))

  button.setBezelStyle(11.NSInteger)
  button.setButtonType(NSButtonType.NSButtonTypeToggle)

  # Set initial button state (0 = off, 1 = on)
  button.setState(if gDiscordEnabled: NSControlStateValueOn else: NSControlStateValueOff)

  let imageName = if gDiscordEnabled: @"gamecontroller.fill" else: @"gamecontroller"
  let image = NSImage.imageWithSystemSymbolName(imageName, imageName)
  if not image.isNil:
    button.setImage(image)

  button.setTitle(@"")  # Empty title, only show icon
  cast[NSButtonCell](button).setImagePosition(nscell.NSCellImagePosition.NSImageOnly)
  cast[NSButtonCell](button).setImageScaling(nscell.NSImageScaling.NSImageScaleProportionallyDown)

  button.setTarget(gDelegateInstance)
  button.setAction(selector("mdcDiscordToggleHandler:"))

  gDiscordButton = button
  gDiscordToolbarItem = item

  let tooltip = if gDiscordEnabled: @"Discord Rich Presence: ON" else: @"Discord Rich Presence: OFF"
  item.setView(button)
  item.setToolTip(tooltip)
  item.setPaletteLabel(@"Discord")

  result = button

proc updateDiscordButtonState*(enabled: bool) =
  ## Update the Discord button state
  gDiscordEnabled = enabled
  if gDiscordButton != nil:
    let imageName = if enabled: @"gamecontroller.fill" else: @"gamecontroller"
    let image = NSImage.imageWithSystemSymbolName(imageName, imageName)
    if not image.isNil:
      gDiscordButton.setImage(image)
    let tooltip = if enabled: @"Discord Rich Presence: ON" else: @"Discord Rich Presence: OFF"
    if not gDiscordToolbarItem.isNil:
      gDiscordToolbarItem.setToolTip(tooltip)

proc mdcToolbarItemForItemIdentifier(self: ID, cmd: SEL, toolbar: ID,
                                   itemIdentifier: NSString,
                                   willBeInsertedIntoToolbar: BOOL): ID {.cdecl.} =
  let identifier = itemIdentifier.UTF8String

  if identifier == "ScanButton":
    if gScanToolbarItem.isNil:
      let item = NSToolbarItem.alloc()
      discard item.initWithItemIdentifier(itemIdentifier)
      item.setEnabled(YES)
      discard createScanButton(item)
      gScanToolbarItem = item
    result = cast[ID](gScanToolbarItem)

  elif identifier == "DiskInfo":
    if gDiskInfoToolbarItem.isNil:
      let item = NSToolbarItem.alloc()
      discard item.initWithItemIdentifier(itemIdentifier)
      createDiskInfoItem(item)
      gDiskInfoToolbarItem = item
    result = cast[ID](gDiskInfoToolbarItem)

  elif identifier == "DiscordButton":
    if gDiscordToolbarItem.isNil:
      let item = NSToolbarItem.alloc()
      discard item.initWithItemIdentifier(itemIdentifier)
      discard createDiscordButton(item)
      gDiscordToolbarItem = item
    result = cast[ID](gDiscordToolbarItem)

  else:
    result = cast[ID](nil)

proc initToolbarDelegate() =
  if gDelegateClass.isNil:
    gDelegateClass = allocateClassPair(getClass("NSObject"), "DevCleanerToolbarDelegate", 0)

    discard addMethod(gDelegateClass, selector("toolbarDefaultItemIdentifiers:"),
      cast[IMP](mdcToolbarDefaultItemIdentifiers), "@@:@")
    discard addMethod(gDelegateClass, selector("toolbarAllowedItemIdentifiers:"),
      cast[IMP](mdcToolbarAllowedItemIdentifiers), "@@:@")
    discard addMethod(gDelegateClass, selector("toolbar:itemForItemIdentifier:willBeInsertedIntoToolbar:"),
      cast[IMP](mdcToolbarItemForItemIdentifier), "@@:@@B")
    discard addMethod(gDelegateClass, selector("mdcScanActionHandler:"),
      cast[IMP](mdcScanActionHandler), "v@:@")
    discard addMethod(gDelegateClass, selector("mdcCleanActionHandler:"),
      cast[IMP](mdcCleanActionHandler), "v@:@")
    discard addMethod(gDelegateClass, selector("mdcDiscordToggleHandler:"),
      cast[IMP](mdcDiscordToggleHandler), "v@:@")

    registerClassPair(gDelegateClass)
    gDelegateInstance = cast[NSObject](objc_msgSend(objc_msgSend(gDelegateClass, selector("alloc")), selector("init")))