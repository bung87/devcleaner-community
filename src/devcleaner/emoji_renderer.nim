## Emoji Renderer using macOS CoreText/CoreGraphics
## Renders emoji characters to textures for NanoVG
## Adapted from crown_excel/src/crown_excel/emoji_renderer.nim

import std/[unicode, tables]
import nanovg
import darwin/objc/runtime
import darwin/[foundation, app_kit, core_graphics]
import darwin/core_text
import darwin/core_foundation/[cfbase, cfstring, cfdictionary, cfattributedstring]

proc isEmoji*(rune: Rune): bool =
  ## Check if a Unicode rune is an emoji character
  let cp = rune.uint32
  # Emoji ranges based on Unicode standard
  # Basic emoji
  if cp >= 0x1F600 and cp <= 0x1F64F: return true  # Emoticons
  if cp >= 0x1F300 and cp <= 0x1F5FF: return true  # Misc Symbols and Pictographs
  if cp >= 0x1F680 and cp <= 0x1F6FF: return true  # Transport and Map
  if cp >= 0x1F1E0 and cp <= 0x1F1FF: return true  # Flags
  if cp >= 0x2600 and cp <= 0x26FF: return true    # Misc symbols
  if cp >= 0x2700 and cp <= 0x27BF: return true    # Dingbats
  if cp >= 0x1F900 and cp <= 0x1F9FF: return true  # Supplemental Symbols and Pictographs
  if cp >= 0x1F018 and cp <= 0x1F270: return true  # Various Asian characters
  if cp >= 0x238C and cp <= 0x2454: return true    # Misc symbols
  if cp >= 0x20D0 and cp <= 0x20FF: return true    # Combining Diacritical Marks for Symbols
  if cp == 0x00A9: return true  # ©
  if cp == 0x00AE: return true  # ®
  if cp == 0x2122: return true  # ™
  if cp >= 0xFE00 and cp <= 0xFE0F: return true    # Variation Selectors
  if cp >= 0x1F3FB and cp <= 0x1F3FF: return true  # Emoji modifiers (skin tones)
  if cp == 0x200D: return true  # Zero Width Joiner (part of emoji sequences)
  if cp == 0x20E3: return true  # Combining enclosing keycap
  return false

type
  EmojiTexture* = object
    imageId*: Image
    width*, height*: int
    advance*: float32

var emojiCache*: TableRef[string, EmojiTexture] = newTable[string, EmojiTexture]()

const
  MaxEmojiCacheSize* = 256  ## Maximum number of emoji textures to cache

# CoreText attributed string and framesetter types
type
  CTFramesetter = ptr object of CFObject
  CTFrame = ptr object of CFObject


# CGSize helper
proc CGSizeMake*(width, height: CGFloat): CGSize {.inline.} =
  result.width = width
  result.height = height

# CGRect helper
proc CGRectMake*(x, y, width, height: CGFloat): CGRect {.inline.} =
  result.origin.x = x
  result.origin.y = y
  result.size.width = width
  result.size.height = height

# CoreText framesetter functions
proc CTFramesetterCreateWithAttributedString*(attrStr: CFAttributedString): CTFramesetter {.importc.}
proc CTFramesetterSuggestFrameSizeWithConstraints*(framesetter: CTFramesetter, stringRange: CFRange, frameAttributes: CFDictionary[CFString, CFObject], constraints: CGSize, fitRange: ptr CFRange): CGSize {.importc.}
proc CTFramesetterCreateFrame*(framesetter: CTFramesetter, stringRange: CFRange, path: CGMutablePath, frameAttributes: CFDictionary[CFString, CFObject]): CTFrame {.importc.}
proc CTFrameDraw*(frame: CTFrame, context: CGContext) {.importc.}

# CoreText attribute keys
var kCTFontAttributeName {.importc.}: CFString

proc pruneEmojiCache*(vg: NVGContext) =
  ## Prune oldest entries when cache exceeds limit (LRU-style: clear half)
  if emojiCache.len > MaxEmojiCacheSize:
    # Simple strategy: clear half the cache when limit reached
    var count = 0
    let halfSize = emojiCache.len div 2
    for emoji, texture in emojiCache:
      if count < halfSize:
        if texture.imageId != NoImage:
          vg.deleteImage(texture.imageId)
        emojiCache.del(emoji)
        count.inc
      else:
        break

proc renderEmojiToTexture*(vg: NVGContext, emoji: string, fontSize: float32): EmojiTexture =
  ## Render an emoji character to a NanoVG texture using macOS CoreGraphics

  # Check cache first
  if emoji in emojiCache:
    return emojiCache[emoji]

  # Create font with specified size
  let cfFontName = CFStringCreate("AppleColorEmoji")
  defer: cfFontName.release()
  let ctFont = CTFontCreateWithName(cfFontName, fontSize, nil)
  defer: ctFont.release()

  # Create attributed string using CoreFoundation
  let attrString = CFAttributedStringCreateMutable(nil, 0)
  defer: attrString.release()

  # Copy emoji string to attributed string
  let cfEmoji = CFStringCreate(emoji)
  defer: cfEmoji.release()
  replaceString(attrString, CFRangeMake(0, 0), cfEmoji)

  # Set font attribute
  let fontRange = CFRangeMake(0, cfEmoji.len)
  setAttribute(attrString, fontRange, kCTFontAttributeName, ctFont)

  # Create framesetter
  let framesetter = CTFramesetterCreateWithAttributedString(attrString)
  defer: framesetter.release()

  # Calculate size needed
  let constraints = CGSizeMake(CGFloat.high, CGFloat.high)
  let suggestedSize = CTFramesetterSuggestFrameSizeWithConstraints(
    framesetter,
    CFRangeMake(0, 0),
    nil,
    constraints,
    nil
  )

  # CoreText returns size in points (logical size), but we need pixels
  # On Retina screens, we need to account for the pixel ratio
  # The fontSize is already in pixels (logical size * pixelRatio)
  # So we use the suggestedSize directly as pixels since we created the font with pixel size
  let width = int(suggestedSize.width + 0.5)
  let height = int(suggestedSize.height + 0.5)

  if width <= 0 or height <= 0:
    return EmojiTexture()

  # Create bitmap context
  let colorSpace = CGColorSpaceCreateDeviceRGB()
  defer: colorSpace.release()

  let bitmapInfo = 1.uint32  # kCGImageAlphaPremultipliedLast
  let context = CGBitmapContextCreate(
    nil,
    width.csize_t,
    height.csize_t,
    8.csize_t,                   # bitsPerComponent: 8 bits per color channel (R/G/B/A)
    (width * 4).csize_t,        # bytesPerRow: width * 4 bytes (RGBA = 4 bytes per pixel)
    colorSpace,
    bitmapInfo
  )

  if context.isNil:
    return EmojiTexture()
  defer: context.release()

  # Clear background (transparent)
  context.setRGBFillColor(0, 0, 0, 0)
  fillRect(context, CGRectMake(0.0, 0.0, CGFloat(width), CGFloat(height)))

  # Create path for text
  let path = CGPathCreateMutable()
  defer: release(path)

  let bounds = CGRectMake(0.0, 0.0, CGFloat(width), CGFloat(height))
  addRect(path, nil, bounds)

  # Create frame and draw
  let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, 0), path, nil)
  defer: frame.release()

  CTFrameDraw(frame, context)

  # Get the image from context
  let cgImage = createImage(context)
  if cgImage.isNil:
    return EmojiTexture()
  defer: release(cgImage)

  # Get raw pixel data
  let data = getData(context)
  if data.isNil:
    return EmojiTexture()

  # Copy data to seq
  var pixelData = newSeq[byte](width * height * 4)
  copyMem(pixelData[0].addr, data, pixelData.len)

  # Create NanoVG image from the pixel data
  let imageId = vg.createImageRGBA(width, height, {ifRepeatX, ifRepeatY}, pixelData)

  result = EmojiTexture(
    imageId: imageId,
    width: width,
    height: height,
    advance: suggestedSize.width.float32
  )

  # Cache the result (with pruning if needed)
  pruneEmojiCache(vg)
  emojiCache[emoji] = result

proc drawEmoji*(vg: NVGContext, x, y: float32, emoji: string, fontSize: float32) =
  ## Draw an emoji at the specified position
  ## The y parameter is the baseline position (same as text)
  let texture = renderEmojiToTexture(vg, emoji, fontSize)
  if texture.imageId == NoImage:
    return

  # Scale emoji to match fontSize
  # Use fontSize as the target height, and scale width proportionally
  let scale = fontSize / texture.height.float32
  let drawWidth = texture.width.float32 * scale
  let drawHeight = fontSize  # Use fontSize directly as height

  # Align emoji to match text baseline
  # Position so the emoji sits on the baseline like regular text
  let drawY = y - drawHeight * 0.5

  let paint = vg.imagePattern(
    x, drawY,
    drawWidth,
    drawHeight,
    0,
    texture.imageId,
    1.0
  )

  vg.beginPath()
  vg.rect(x, drawY, drawWidth, drawHeight)
  vg.fillPaint(paint)
  vg.fill()

proc measureEmoji*(vg: NVGContext, emoji: string, fontSize: float32): float32 =
  ## Measure the width of an emoji
  let texture = renderEmojiToTexture(vg, emoji, fontSize)
  # Scale width to match the scaled height (fontSize)
  let scale = fontSize / texture.height.float32
  return texture.width.float32 * scale

proc clearEmojiCache*(vg: NVGContext) =
  ## Clear the emoji texture cache and free resources
  for _, texture in emojiCache:
    if texture.imageId != NoImage:
      vg.deleteImage(texture.imageId)
  emojiCache.clear()
