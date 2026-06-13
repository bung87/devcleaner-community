## Icon Cache Module
## Pre-renders icons to GPU textures for optimal performance
## Instead of drawing vector paths every frame, we use cached textures

import nanovg
import ./icons
import ./theme

export nanovg.Image

type
  IconKind* = enum
    ikTrash
    ikTrashSmall
    ikInfo
    ikChevronRight

  IconCache* = object
    ## Cache for pre-rendered icon textures
    ## Stores two color variants: normal and hover
    normalIcons*: array[IconKind, NVGLUFramebuffer]
    hoverIcons*: array[IconKind, NVGLUFramebuffer]
    initialized*: bool

var iconCache*: IconCache

proc renderIconToFBO(vg: NVGContext, kind: IconKind, size: float32, color: Color): NVGLUFramebuffer =
  ## Render an icon to a framebuffer object
  ## Returns the FBO handle with attached image
  let texSize = (size * 2).int  # Double size for retina
  let actualSize = texSize.float32
  let halfSize = actualSize / 2.0
  
  # Create FBO with image
  result = nvgluCreateFramebuffer(vg, texSize, texSize, {ifPremultiplied})
  if result.isNil:
    return nil
  
  # Bind FBO for rendering
  nvgluBindFramebuffer(result)
  
  # Set up viewport
  vg.beginFrame(actualSize, actualSize, 1.0)
  
  # Clear with transparent
  vg.beginPath()
  vg.rect(0, 0, actualSize, actualSize)
  vg.fillColor(Color(r: 0, g: 0, b: 0, a: 0))
  vg.fill()
  
  # Draw icon centered
  case kind
  of ikTrash:
    drawTrashIcon(vg, halfSize - size/2, halfSize - size/2, size, color)
  of ikTrashSmall:
    drawTrashIcon(vg, halfSize - size/2, halfSize - size/2, size, color)
  of ikInfo:
    drawInfoIcon(vg, halfSize - size/2, halfSize - size/2, size, color)
  of ikChevronRight:
    drawChevronRight(vg, halfSize - size/2, halfSize - size/2, size, color)
  
  vg.endFrame()
  
  # Unbind FBO
  nvgluBindFramebuffer(nil)

proc initIconCache*(vg: NVGContext) =
  ## Initialize icon cache with pre-rendered textures
  ## Must be called after theme is initialized
  if iconCache.initialized:
    return
  
  let theme = getCurrentTheme()
  
  # Define icon sizes
  const sizes: array[IconKind, float32] = [
    20.0,  # ikTrash
    16.0,  # ikTrashSmall
    16.0,  # ikInfo
    20.0,  # ikChevronRight
  ]
  
  # Render normal (muted) and hover (accent) variants
  for kind in IconKind:
    let size = sizes[kind]
    iconCache.normalIcons[kind] = renderIconToFBO(vg, kind, size, theme.textMuted)
    iconCache.hoverIcons[kind] = renderIconToFBO(vg, kind, size, theme.accent)
  
  iconCache.initialized = true

proc refreshIconCache*(vg: NVGContext) =
  ## Refresh icon cache when theme changes
  ## Call this after theme update
  if not iconCache.initialized:
    initIconCache(vg)
    return
  
  let theme = getCurrentTheme()
  
  const sizes: array[IconKind, float32] = [
    20.0,  # ikTrash
    16.0,  # ikTrashSmall
    16.0,  # ikInfo
    20.0,  # ikChevronRight
  ]
  
  # Delete old FBOs and create new ones
  for kind in IconKind:
    if iconCache.normalIcons[kind] != nil:
      nvgluDeleteFramebuffer(iconCache.normalIcons[kind])
    if iconCache.hoverIcons[kind] != nil:
      nvgluDeleteFramebuffer(iconCache.hoverIcons[kind])
    
    let size = sizes[kind]
    iconCache.normalIcons[kind] = renderIconToFBO(vg, kind, size, theme.textMuted)
    iconCache.hoverIcons[kind] = renderIconToFBO(vg, kind, size, theme.accent)

proc drawCachedIcon*(vg: NVGContext, kind: IconKind, x, y, size: float32, isHovered: bool, alpha: float32 = 1.0) =
  ## Draw a cached icon texture
  ## x, y is the top-left position
  ## size is the target display size
  let fbo = if isHovered: iconCache.hoverIcons[kind] else: iconCache.normalIcons[kind]
  if fbo.isNil or fbo.image == NoImage:
    return
  
  let paint = vg.imagePattern(x, y, size, size, 0.0, fbo.image, alpha)
  vg.beginPath()
  vg.rect(x, y, size, size)
  vg.fillPaint(paint)
  vg.fill()

proc cleanupIconCache*(vg: NVGContext) =
  ## Free all cached icon textures
  for kind in IconKind:
    if iconCache.normalIcons[kind] != nil:
      nvgluDeleteFramebuffer(iconCache.normalIcons[kind])
      iconCache.normalIcons[kind] = nil
    if iconCache.hoverIcons[kind] != nil:
      nvgluDeleteFramebuffer(iconCache.hoverIcons[kind])
      iconCache.hoverIcons[kind] = nil
  iconCache.initialized = false
