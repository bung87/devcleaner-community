## Rendering Module
## Provides convenient drawing primitives and text rendering using NanoVG
## Refactored based on bookmarkey's rendering system

import std/[unicode, strutils]
import nanovg
import ./fonts
import ./emoji_renderer

export nanovg.Color, nanovg.Font, nanovg.NoFont
export emoji_renderer.isEmoji, emoji_renderer.drawEmoji, emoji_renderer.measureEmoji, emoji_renderer.clearEmojiCache

# Basic shape drawing procs
proc drawRect*(vg: NVGContext, x, y, w, h: float32, color: Color) =
  vg.beginPath()
  vg.rect(x, y, w, h)
  vg.fillColor(color)
  vg.fill()

proc drawRoundedRect*(vg: NVGContext, x, y, w, h, radius: float32, color: Color) =
  vg.beginPath()
  vg.roundedRect(x, y, w, h, radius)
  vg.fillColor(color)
  vg.fill()

proc drawRoundedRectStroke*(vg: NVGContext, x, y, w, h, radius, strokeWidth: float32, strokeColor: Color) =
  ## Draw only the stroke of a rounded rectangle
  vg.beginPath()
  vg.roundedRect(x, y, w, h, radius)
  vg.strokeColor(strokeColor)
  vg.strokeWidth(strokeWidth)
  vg.stroke()

proc drawRoundedRectFillStroke*(vg: NVGContext, x, y, w, h, radius, strokeWidth: float32, fillColor, strokeColor: Color) =
  ## Draw a rounded rectangle with both fill and stroke
  vg.beginPath()
  vg.roundedRect(x, y, w, h, radius)
  vg.fillColor(fillColor)
  vg.fill()
  vg.strokeColor(strokeColor)
  vg.strokeWidth(strokeWidth)
  vg.stroke()

proc drawCircle*(vg: NVGContext, cx, cy, r: float32, color: Color) =
  vg.beginPath()
  vg.circle(cx, cy, r)
  vg.fillColor(color)
  vg.fill()

proc drawLine*(vg: NVGContext, x1, y1, x2, y2, width: float32, color: Color) =
  vg.beginPath()
  vg.moveTo(x1, y1)
  vg.lineTo(x2, y2)
  vg.strokeColor(color)
  vg.strokeWidth(width)
  vg.stroke()

proc drawBoxGradient*(vg: NVGContext, x, y, w, h, r, f: float32, icol, ocol: Color) =
  let paint = vg.boxGradient(x, y, w, h, r, f, icol, ocol)
  vg.beginPath()
  vg.rect(x - 10, y - 10, w + 20, h + 20)
  vg.fillPaint(paint)
  vg.fill()

proc drawRadialGradient*(vg: NVGContext, cx, cy, inr, outr: float32, icol, ocol: Color) =
  let paint = vg.radialGradient(cx, cy, inr, outr, icol, ocol)
  vg.beginPath()
  vg.rect(cx - outr, cy - outr, outr * 2, outr * 2)
  vg.fillPaint(paint)
  vg.fill()

# Internal helper: draw text without dynamic font lookup (font already resolved)
proc drawTextRaw(vg: NVGContext, x, y: float32, text: string, fontSize: float32, color: Color, font: Font) =
  ## Draw text with given font (no dynamic font loading)
  vg.fontSize(fontSize)
  vg.fontFace(font)
  vg.fillColor(color)
  vg.textAlign(haLeft, vaMiddle)
  discard vg.text(x, y, text)
  vg.textAlign(haLeft, vaBaseline)

# Text drawing procs with dynamic font loading
proc drawText*(vg: NVGContext, x, y: float32, text: string, fontSize: float32, color: Color, font: Font = NoFont) =
  ## Draw text with dynamic font loading for multi-language support
  ## Optimized: uses reusable buffer to minimize allocations
  ## If font is NoFont, uses the default font from fonts module
  vg.fontSize(fontSize)
  let actualFont = if font != NoFont: font else: getDefaultFont()
  vg.fillColor(color)
  vg.textAlign(haLeft, vaMiddle)
  
  var currentX = x
  var currentFont = actualFont
  
  # Thread-local reusable buffer to avoid per-call allocation
  var buffer {.threadvar.}: string
  buffer.setLen(0)
  # Pre-allocate capacity (UTF-8 max 4 bytes per rune)
  if buffer.len < text.len * 4:
    buffer.setLen(text.len * 4)
  buffer.setLen(0)
  
  for r in text.runes:
    let charStr = $r
    let charFont = getFontForString(vg, actualFont, charStr)
    
    if charFont != currentFont and buffer.len > 0:
      # Flush buffer
      vg.fontFace(currentFont)
      discard vg.text(currentX, y, buffer)
      # Measure width for advance
      let (bounds, _) = vg.textBounds(currentX, y, buffer)
      currentX = bounds.x2
      buffer.setLen(0)
    
    currentFont = charFont
    buffer.add(charStr)
  
  # Flush remaining characters
  if buffer.len > 0:
    vg.fontFace(currentFont)
    discard vg.text(currentX, y, buffer)
  
  vg.textAlign(haLeft, vaBaseline)

proc drawTextCentered*(vg: NVGContext, x, y: float32, text: string, fontSize: float32, color: Color, font: Font = NoFont) =
  ## Draw centered text with dynamic font loading
  vg.fontSize(fontSize)
  let actualFont = if font != NoFont: font else: getDefaultFont()
  # Use dynamic font loading to get suitable font
  let segmentFont = getFontForString(vg, actualFont, text)
  if segmentFont != NoFont:
    vg.fontFace(segmentFont)
  vg.textAlign(haCenter, vaMiddle)
  vg.fillColor(color)
  discard vg.text(x, y, text)
  vg.textAlign(haLeft, vaBaseline)

proc measureText*(vg: NVGContext, text: string, fontSize: float32, font: Font = NoFont): float32 =
  ## Measure text width with dynamic font loading
  vg.fontSize(fontSize)
  let actualFont = if font != NoFont: font else: getDefaultFont()
  # Use dynamic font loading to get suitable font
  let segmentFont = getFontForString(vg, actualFont, text)
  if segmentFont != NoFont:
    vg.fontFace(segmentFont)
  let (bounds, _) = vg.textBounds(0, 0, text)
  return bounds.x2.float32 - bounds.x1.float32

proc truncateText*(vg: NVGContext, text: string, fontSize: float32, font: Font, maxWidth: float32): string =
  ## Truncate text with ellipsis if it exceeds maxWidth
  if text.len == 0:
    return ""

  let textWidth = measureText(vg, text, fontSize, font)
  if textWidth <= maxWidth:
    return text

  var low = 0
  var high = text.len
  var mid: int

  while low <= high:
    mid = (low + high) div 2
    let substr = text[0..<mid] & "..."
    let width = measureText(vg, substr, fontSize, font)

    if width <= maxWidth:
      low = mid + 1
    else:
      high = mid - 1

  if low > 0:
    result = text[0..<low] & "..."
  else:
    result = "..."



proc drawTextWithEmoji*(vg: NVGContext, x, y: float32, text: string, fontSize: float32, color: Color, font: Font = NoFont) =
  ## Draw text with emoji support and dynamic font loading for CJK
  var currentX = x
  var currentText = ""
  let actualFont = if font != NoFont: font else: getDefaultFont()

  # Pre-allocate buffer capacity to minimize reallocations
  currentText.setLen(text.len + 16)  # Upper bound + padding
  currentText.setLen(0)

  for r in text.runes:
    if isEmoji(r):
      # Flush current text buffer
      if currentText.len > 0:
        let segmentFont = getFontForString(vg, actualFont, currentText)
        drawTextRaw(vg, currentX, y, currentText, fontSize, color, segmentFont)
        currentX += measureText(vg, currentText, fontSize, segmentFont)
        currentText.setLen(0)
      # Draw emoji
      let emojiStr = $r
      drawEmoji(vg, currentX, y, emojiStr, fontSize)
      currentX += measureEmoji(vg, emojiStr, fontSize)
    else:
      currentText.add($r)

  # Flush remaining text
  if currentText.len > 0:
    let segmentFont = getFontForString(vg, actualFont, currentText)
    drawTextRaw(vg, currentX, y, currentText, fontSize, color, segmentFont)

proc measureTextWithEmoji*(vg: NVGContext, text: string, fontSize: float32, font: Font = NoFont): float32 =
  ## Measure text width with emoji support and dynamic font loading
  var totalWidth = 0.0f
  var currentText = ""
  let actualFont = if font != NoFont: font else: getDefaultFont()

  # Pre-allocate buffer capacity
  currentText.setLen(text.len + 16)
  currentText.setLen(0)

  for r in text.runes:
    if isEmoji(r):
      # Flush current text buffer
      if currentText.len > 0:
        let segmentFont = getFontForString(vg, actualFont, currentText)
        totalWidth += measureText(vg, currentText, fontSize, segmentFont)
        currentText.setLen(0)
      totalWidth += measureEmoji(vg, $r, fontSize)
    else:
      currentText.add($r)

  # Flush remaining text
  if currentText.len > 0:
    let segmentFont = getFontForString(vg, actualFont, currentText)
    totalWidth += measureText(vg, currentText, fontSize, segmentFont)

  return totalWidth

# Image creation and drawing procs
proc createImageFromRGBA*(vg: NVGContext, width, height: int, data: sink seq[uint8]): nanovg.Image =
  ## Create an image from RGBA data
  ## Uses sink parameter to avoid unnecessary copying - ORC will move the data
  result = nanovg.NoImage
  if data.len < width * height * 4:
    return nanovg.NoImage

  # data is sink, so it's moved (not copied) to createImageRGBA
  result = vg.createImageRGBA(width, height, {}, data)

proc drawImage*(vg: NVGContext, img: nanovg.Image, x, y, w, h: float32) =
  ## Draw an image at the specified position and size using nanovg.Image handle
  if img == nanovg.NoImage:
    return

  let paint = vg.imagePattern(x, y, w, h, 0.0, img, 1.0)
  vg.beginPath()
  vg.rect(x, y, w, h)
  vg.fillPaint(paint)
  vg.fill()

proc drawRibbonBanner*(vg: NVGContext, x, y, w, h, notchSize, rightOffset, scale: float32,
                       color: Color, bgAlpha: float32) =
  ## Draw a ribbon banner with notch and gradient fill
  let notchX = x + w - rightOffset * scale - notchSize
  let notchTipX = x + w - rightOffset * scale
  let centerY = y + h * 0.5

  vg.beginPath()
  vg.moveTo(x, y)
  vg.lineTo(notchX, y)
  vg.lineTo(notchTipX, centerY)
  vg.lineTo(notchX, y + h)
  vg.lineTo(x, y + h)
  vg.closePath()

  let ribbonPaint = vg.linearGradient(x, y, x, y + h,
    color.withAlpha(bgAlpha),
    Color(r: color.r * 0.85, g: color.g * 0.85, b: color.b * 0.85, a: bgAlpha))
  vg.fillPaint(ribbonPaint)
  vg.fill()

  # Top highlight line
  vg.beginPath()
  vg.moveTo(x + scale, y + scale)
  vg.lineTo(notchX, y + scale)
  vg.strokeColor(Color(r: 1.0, g: 1.0, b: 1.0, a: 0.4 * bgAlpha))
  vg.strokeWidth(scale)
  vg.stroke()

  # Bottom shadow line
  vg.beginPath()
  vg.moveTo(x + scale, y + h - scale)
  vg.lineTo(notchX, y + h - scale)
  vg.strokeColor(Color(r: 0, g: 0, b: 0, a: 0.15 * bgAlpha))
  vg.strokeWidth(scale)
  vg.stroke()
