import std/[sequtils, tables, os]
import nglfw
import nanovg
import nanovg/wrapper as nvgWrapper
import pixie except Color
import ./fonts
import ./rendering

export nglfw
export Color
export nanovg.Font, nanovg.NoFont

# GLFW native access for macOS (statically linked)
proc glfwGetCocoaWindow(window: pointer): pointer {.cdecl, importc.}

type GNVGWindow* = ref object
  glfwWindow*: Window
  vg*: nanovg.NVGContext
  width*, height*: int
  framebufferWidth*, framebufferHeight*: int
  pixelRatio*: float32
  mouseX*, mouseY*: float64
  mouseDown*: bool
  mousePressed*: bool
  mouseReleased*: bool
  wheelX*, wheelY*: float64
  keysPressed*: seq[int]
  keysReleased*: seq[int]
  keysDown*: seq[int]
  filesDropped*: bool
  droppedFiles*: seq[string]

proc mouseXScaled*(win: GNVGWindow): float32 =
  ## Get mouse X coordinate scaled for Retina displays
  return win.mouseX.float32 * win.pixelRatio

proc mouseYScaled*(win: GNVGWindow): float32 =
  ## Get mouse Y coordinate scaled for Retina displays
  return win.mouseY.float32 * win.pixelRatio

proc createWindow*(width, height: int, title: string, resizable: bool = true): GNVGWindow =
  result = GNVGWindow()
  result.width = width
  result.height = height

  # Initialize GLFW
  discard init()

  defaultWindowHints()
  windowHint(CLIENT_API, OPENGL_API)
  windowHint(CONTEXT_VERSION_MAJOR, 3)
  windowHint(CONTEXT_VERSION_MINOR, 2)
  windowHint(OPENGL_PROFILE, OPENGL_CORE_PROFILE)
  windowHint(OPENGL_FORWARD_COMPAT, 1)
  windowHint(RESIZABLE, if resizable: 1 else: 0)

  let handle = createWindow(width.cint, height.cint, title.cstring, nil, nil)
  if handle == nil:
    raise newException(OSError, "Failed to create GLFW window")

  result.glfwWindow = handle

  makeContextCurrent(handle)
  swapInterval(1)

  nanovg.nvgInit(cast[pointer](getProcAddress))

  result.vg = nanovg.nvgCreateContext({nifAntialias, nifStencilStrokes})
  if result.vg == nil:
    raise newException(OSError, "Failed to create NanoVG context")

  loadFonts(result.vg)

  var fbw, fbh, ww, wh: cint
  getFramebufferSize(handle, addr fbw, addr fbh)
  getWindowSize(handle, addr ww, addr wh)
  result.framebufferWidth = fbw.int
  result.framebufferHeight = fbh.int
  result.pixelRatio = fbw.float32 / ww.float32

var gWindowTable*: Table[Window, GNVGWindow]

proc destroy*(win: GNVGWindow) =
  let handle = win.glfwWindow
  gWindowTable.del(handle)

  if win.vg != nil:
    win.vg.nvgDeleteContext()
  destroyWindow(handle)
  terminate()

proc shouldClose*(win: GNVGWindow): bool =
  windowShouldClose(win.glfwWindow)

proc setShouldClose*(win: GNVGWindow, value: bool) =
  setWindowShouldClose(win.glfwWindow, value)

proc setTitle*(win: GNVGWindow, title: string) =
  setWindowTitle(win.glfwWindow, title.cstring)

proc getNativeHandle*(win: GNVGWindow): pointer =
  result = glfwGetCocoaWindow(win.glfwWindow)

proc swapBuffers*(win: GNVGWindow) =
  swapBuffers(win.glfwWindow)

proc getSize*(win: GNVGWindow): (int, int) =
  var ww, wh: cint
  getWindowSize(win.glfwWindow, addr ww, addr wh)
  result = (ww.int, wh.int)

proc getFramebufferSize*(win: GNVGWindow): (int, int) =
  var fbw, fbh: cint
  getFramebufferSize(win.glfwWindow, addr fbw, addr fbh)
  result = (fbw.int, fbh.int)

proc updateSize*(win: GNVGWindow) =
  let (w, h) = win.getSize()
  win.width = w
  win.height = h
  let (fbw, fbh) = win.getFramebufferSize()
  win.framebufferWidth = fbw
  win.framebufferHeight = fbh
  win.pixelRatio = fbw.float32 / w.float32

proc getCursorPos*(win: GNVGWindow): (float64, float64) =
  var x, y: cdouble
  getCursorPos(win.glfwWindow, addr x, addr y)
  result = (x, y)

var cursorCache: Table[cint, CursorHandle]

type CursorShape* = enum
  csArrow = ARROW_CURSOR
  csIBeam = IBEAM_CURSOR
  csCrosshair = CROSSHAIR_CURSOR
  csHand = HAND_CURSOR
  csResizeEW = HRESIZE_CURSOR
  csResizeNS = VRESIZE_CURSOR

proc setCursor*(win: GNVGWindow, shape: CursorShape) =
  var cursor: CursorHandle
  let shapeCint = shape.cint
  if shapeCint in cursorCache:
    cursor = cursorCache[shapeCint]
  else:
    cursor = createStandardCursor(shapeCint)
    if cursor != nil:
      cursorCache[shapeCint] = cursor

  if cursor != nil:
    setCursor(win.glfwWindow, cursor)

proc isMouseButtonDown*(win: GNVGWindow, button: int): bool =
  let mb = case button
    of 0: MOUSE_BUTTON_LEFT
    of 1: MOUSE_BUTTON_RIGHT
    of 2: MOUSE_BUTTON_MIDDLE
    else: MOUSE_BUTTON_LEFT
  getMouseButton(win.glfwWindow, mb.cint) == PRESS

proc isKeyDown*(win: GNVGWindow, key: int): bool =
  getKey(win.glfwWindow, key.cint) == PRESS

proc getAndClearScrollDelta*(win: GNVGWindow, pixelRatio: float32): (float32, float32) =
  let rawDeltaX = win.wheelX
  let rawDeltaY = win.wheelY
  win.wheelX = 0
  win.wheelY = 0
  result = (rawDeltaX.float32 * 3.0, rawDeltaY.float32 * 3.0)

proc beginFrame*(win: GNVGWindow) =
  win.vg.beginFrame(win.framebufferWidth.float32, win.framebufferHeight.float32, win.pixelRatio)

proc beginFrameLogical*(win: GNVGWindow) =
  win.vg.beginFrame(win.width.float32, win.height.float32, 1.0)

proc endFrame*(win: GNVGWindow) =
  win.vg.endFrame()

proc save*(win: GNVGWindow) =
  win.vg.save()

proc loadImage*(win: GNVGWindow, path: string): nanovg.Image =
  ## Load an image from file (PNG, JPG, etc.)
  result = nanovg.NoImage
  if not fileExists(path):
    return nanovg.NoImage

  try:
    let img = pixie.readImage(path)
    let width = img.width
    let height = img.height

    # Convert to RGBA data - pixie stores as RGBX (4 bytes per pixel)
    var data = newSeq[uint8](width * height * 4)
    for y in 0..<height:
      for x in 0..<width:
        let color = img[x, y] # Returns ColorRGBX
        let idx = (y * width + x) * 4
        data[idx] = color.r
        data[idx + 1] = color.g
        data[idx + 2] = color.b
        data[idx + 3] = color.a

    result = rendering.createImageFromRGBA(win.vg, width, height, data)
  except:
    result = nanovg.NoImage

proc globalScrollCb(handle: Window, xOffset, yOffset: cdouble) {.cdecl.} =
  if handle in gWindowTable:
    let win = gWindowTable[handle]
    win.wheelX += xOffset
    win.wheelY += yOffset

proc globalMouseButtonCb(handle: Window, button, action, modKeys: cint) {.cdecl.} =
  if handle in gWindowTable:
    let win = gWindowTable[handle]
    if action == PRESS:
      win.mouseDown = true
      win.mousePressed = true
    else:
      win.mouseDown = false
      win.mouseReleased = true

proc globalCursorPosCb(handle: Window, x, y: cdouble) {.cdecl.} =
  if handle in gWindowTable:
    let win = gWindowTable[handle]
    win.mouseX = x.float64
    win.mouseY = y.float64

proc globalKeyCb(handle: Window, key, scanCode, action, modKeys: cint) {.cdecl.} =
  if handle in gWindowTable:
    let win = gWindowTable[handle]
    if action == PRESS:
      win.keysPressed.add(key.int)
      if key.int notin win.keysDown:
        win.keysDown.add(key.int)
    elif action == RELEASE:
      win.keysReleased.add(key.int)
      win.keysDown.keepItIf(it != key.int)

proc globalDropCb(handle: Window, count: cint, paths: cstringArray) {.cdecl.} =
  if handle in gWindowTable:
    let win = gWindowTable[handle]
    win.droppedFiles = newSeq[string](count.int)
    for i in 0..<count.int:
      win.droppedFiles[i] = $paths[i]
    win.filesDropped = true

proc globalFramebufferSizeCb(handle: Window, width, height: cint) {.cdecl.} =
  if handle in gWindowTable:
    let win = gWindowTable[handle]
    win.framebufferWidth = width.int
    win.framebufferHeight = height.int
    let (ww, wh) = win.getSize()
    win.width = ww
    win.height = wh
    if ww > 0:
      win.pixelRatio = width.float32 / ww.float32

proc setupCallbacks*(win: GNVGWindow) =
  let handle = win.glfwWindow
  gWindowTable[handle] = win
  discard setScrollCallback(handle, globalScrollCb)
  discard setMouseButtonCallback(handle, globalMouseButtonCb)
  discard setCursorPosCallback(handle, globalCursorPosCb)
  discard setKeyCallback(handle, globalKeyCb)
  setDropCallback(handle, globalDropCb)
  discard setFramebufferSizeCallback(handle, globalFramebufferSizeCb)

proc clearInputState*(win: GNVGWindow) =
  win.mousePressed = false
  win.mouseReleased = false
  win.keysPressed.setLen(0)
  win.keysReleased.setLen(0)
  win.filesDropped = false
  win.droppedFiles.setLen(0)
