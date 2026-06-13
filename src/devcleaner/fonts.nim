## Font loading utilities for GLFW + NanoVG
## Refactored based on bookmarkey's font system

import std/[os, strutils, unicode, tables]
import chronicles
import nanovg
import darwin/objc/runtime
import darwin/[foundation, app_kit]
import darwin/core_foundation/[cfbase, cfstring, cfarray, cfdictionary]
import darwin/core_text
import ./utils

# Direct C function import to avoid Nim wrapper recursion bug
proc nvgCreateFontAtIndexC(ctx: pointer, name: cstring, filename: cstring, fontIndex: cint): cint {.cdecl, importc: "nvgCreateFontAtIndex".}

type
  FontCategory* = enum
    fcSansSerif
    fcMonospace

  FontWeight* = enum
    ## Font weight variants (ordinal values 0-8, use weightValue() to get CSS weight)
    fwThin
    fwExtraLight
    fwLight
    fwRegular
    fwMedium
    fwSemiBold
    fwBold
    fwExtraBold
    fwBlack

  FontStyle* = enum
    ## Font style variants
    fsNormal
    fsItalic

  FontError* = object of CatchableError

proc weightNumber*(w: FontWeight): int =
  ## Get OpenType weight class value (100-900)
  case w
  of fwThin:       100
  of fwExtraLight: 200
  of fwLight:      300
  of fwRegular:    400
  of fwMedium:     500
  of fwSemiBold:   600
  of fwBold:       700
  of fwExtraBold:  800
  of fwBlack:      900

var
  # Font tables: category -> (weight, style) -> Font
  gFontTable*: TableRef[FontCategory, TableRef[(FontWeight, FontStyle), Font]] = newTable[FontCategory, TableRef[(FontWeight, FontStyle), Font]]()

  # Dynamic font loading cache
  gFontNameToHandle*: TableRef[string, Font] = newTable[string, Font]()  # PostScript name -> NVG Font
  gFontHandleToName*: TableRef[Font, string] = newTable[Font, string]()  # NVG Font -> PostScript name
  gDynamicFontsLoaded*: TableRef[string, bool] = newTable[string, bool]()  # Already dynamically loaded fonts

proc getFont*(category: FontCategory, weight: FontWeight = fwRegular, style: FontStyle = fsNormal): Font =
  ## Get font for category with specific weight and style
  if category notin gFontTable:
    raise newException(FontError, "Font not loaded for category: " & $category)
  let weightTable = gFontTable[category]
  let key = (weight, style)
  if key in weightTable:
    return weightTable[key]
  # Fallback to regular weight with same style
  if (fwRegular, style) in weightTable:
    return weightTable[(fwRegular, style)]
  # Fallback to requested weight with normal style
  if (weight, fsNormal) in weightTable:
    return weightTable[(weight, fsNormal)]
  # Fallback to regular weight with normal style (most common)
  if (fwRegular, fsNormal) in weightTable:
    return weightTable[(fwRegular, fsNormal)]
  # Fallback to any available font in this category
  for _, font in weightTable:
    return font
  raise newException(FontError, "No font available for category: " & $category)

proc getDefaultFont*(weight: FontWeight = fwRegular, style: FontStyle = fsNormal): Font =
  ## Get the default font (fcSansSerif) with specified weight and style
  return getFont(fcSansSerif, weight, style)

proc getMonospaceFont*(weight: FontWeight = fwRegular, style: FontStyle = fsNormal): Font =
  ## Get monospace font with specified weight and style
  return getFont(fcMonospace, weight, style)

proc hasFontLoaded*(): bool =
  result = gFontTable.len > 0

# Deprecated: kept for backward compatibility
proc getFontForCategory*(category: FontCategory): Font =
  ## Get regular font for category (deprecated, use getFont instead)
  return getFont(category, fwRegular, fsNormal)

proc getFontPathFromCTFont(ctFont: CTFont): string =
  if ctFont.isNil:
    raise newException(FontError, "CTFont is nil")

  let descriptor = copyFontDescriptor(ctFont)
  if descriptor.isNil:
    raise newException(FontError, "Failed to copy font descriptor")
  defer: descriptor.release()

  let urlRef = copyAttribute(descriptor, kCTFontURLAttribute)
  if urlRef.isNil:
    raise newException(FontError, "Failed to get font URL attribute")
  defer: urlRef.release()

  let url = cast[NSURL](urlRef)
  let path = url.fileSystemRepresentation()

  result = $path
  if result.len == 0:
    raise newException(FontError, "Font path is empty")

proc CFLocaleCopyPreferredLanguages(): CFArray[CFString] {.importc.}

# Runtime cache for TTC font indices: (path, fontName) -> index
var gTTCFontIndexCache: TableRef[(string, string), int] = newTable[(string, string), int]()

proc loadFontFromFile(vg: NVGContext, ctFont: CTFont, fontName: string): Font =
  let path = getFontPathFromCTFont(ctFont)
  info "Loading font", font = fontName
  debug "Font file path", path = path
  
  # Check if it's a TrueType Collection (.ttc) file
  if path.endsWith(".ttc"):
    let cacheKey = (path, fontName)
    var startIndex = 0
    
    # Check if we have a cached index for this font
    if cacheKey in gTTCFontIndexCache:
      startIndex = gTTCFontIndexCache[cacheKey]
      debug "TTC cache hit", startIndex = startIndex
    else:
      debug "TTC cache miss, searching indices"
    
    # Try to load font starting from startIndex
    var handle: cint = 0
    var usedIndex = -1
    
    # Try startIndex first
    handle = nvgCreateFontAtIndexC(cast[pointer](vg), fontName.cstring, path.cstring, startIndex.cint)
    if handle > 0:
      usedIndex = startIndex
    
    # If that fails, try other indices 0-50
    if handle <= 0:
      for index in 0..50:
        if index == startIndex:
          continue
        handle = nvgCreateFontAtIndexC(cast[pointer](vg), fontName.cstring, path.cstring, index.cint)
        if handle > 0:
          usedIndex = index
          # Cache the successful index for future use
          gTTCFontIndexCache[cacheKey] = index
          break
    
    if handle <= 0:
      error "Font loading failed", font = fontName
      raise newException(FontError, "Failed to create font from TTC: " & fontName)
    debug "Font loaded", font = fontName, handle = handle, index = usedIndex
    result = handle.Font
  else:
    let handle = vg.createFont(fontName, path)
    if handle.int <= 0:
      error "Font loading failed", font = fontName
      raise newException(FontError, "Failed to create font: " & fontName)
    debug "Font loaded", font = fontName, handle = handle.int
    result = handle

proc getCTFontForLanguage(uiType: CTFontUIFontType, language: CFString): CTFont =
  result = CTFontCreateUIFontForLanguage(uiType, 12.0, language)
  if result.isNil:
    let langStr = if language.isNil: "nil" else: $language
    raise newException(FontError, "CTFontCreateUIFontForLanguage returned nil for language: " & langStr)

proc loadUIFontForLanguage(vg: NVGContext, uiType: CTFontUIFontType, language: CFString): Font =
  let ctFont = getCTFontForLanguage(uiType, language)
  defer: ctFont.release()

  let psName = ctFont.copyPostScriptName()
  if psName.isNil:
    let langStr = if language.isNil: "nil" else: $language
    raise newException(FontError, "Failed to get PostScript name for language: " & langStr)
  defer: psName.release()

  let fontName = $psName
  
  # Check if already loaded
  if fontName in gFontNameToHandle:
    return gFontNameToHandle[fontName]
  
  result = loadFontFromFile(vg, ctFont, fontName)
  
  # Fill font mapping table for dynamic font loading
  gFontNameToHandle[fontName] = result
  gFontHandleToName[result] = fontName

proc getPreferredLanguages(): CFArray[CFString] =
  result = CFLocaleCopyPreferredLanguages()
  if result.isNil:
    raise newException(FontError, "CFLocaleCopyPreferredLanguages returned nil")

proc initFontTableForCategory(category: FontCategory) =
  ## Initialize empty font table for a category
  if category notin gFontTable:
    gFontTable[category] = newTable[(FontWeight, FontStyle), Font]()

proc loadSystemFonts(vg: NVGContext, categories: set[FontCategory] = {fcSansSerif, fcMonospace}) =
  ## Load system fonts as fallback for categories not loaded by Inter
  ## Only loads regular weight, system fonts don't have easy weight selection
  let preferredLangs = getPreferredLanguages()
  defer: preferredLangs.release()

  let count = preferredLangs.len()
  if count == 0:
    raise newException(FontError, "No preferred languages found")

  # Load sans-serif font (only if Inter didn't load any fonts)
  if fcSansSerif in categories:
    # Check if any fonts were loaded for this category
    var hasSansFonts = false
    if fcSansSerif in gFontTable:
      hasSansFonts = gFontTable[fcSansSerif].len > 0
    
    if not hasSansFonts:
      initFontTableForCategory(fcSansSerif)
      var sansFontLoaded = false
      var lastError: ref FontError = nil
      for i in 0 ..< count:
        let lang = preferredLangs[i]
        if lang.isNil:
          continue
        try:
          let font = loadUIFontForLanguage(vg, kCTFontUIFontSystem, lang)
          gFontTable[fcSansSerif][(fwRegular, fsNormal)] = font
          sansFontLoaded = true
          debug "System font loaded", type = "sans-serif", language = $lang
          break
        except FontError as e:
          lastError = e
      if not sansFontLoaded:
        raise newException(FontError, "Failed to load sans-serif font: " & lastError.msg)

  # Load monospace font
  if fcMonospace in categories:
    initFontTableForCategory(fcMonospace)
    var monoFontLoaded = false
    for i in 0 ..< count:
      let lang = preferredLangs[i]
      if lang.isNil:
        continue
      if (fwRegular, fsNormal) in gFontTable[fcMonospace]: break
      try:
        let font = loadUIFontForLanguage(vg, kCTFontUIFontUserFixedPitch, lang)
        gFontTable[fcMonospace][(fwRegular, fsNormal)] = font
        monoFontLoaded = true
        debug "System font loaded", type = "monospace", language = $lang
        break
      except FontError:
        discard
    if not monoFontLoaded:
      raise newException(FontError, "Failed to load monospace font")

proc loadFonts*(vg: NVGContext) =
  ## Load all fonts - system fonts only
  loadSystemFonts(vg, {fcSansSerif, fcMonospace})

  # Check what we loaded
  var sansLoaded = false
  var monoLoaded = false
  var regularLoaded = false
  if fcSansSerif in gFontTable:
    sansLoaded = gFontTable[fcSansSerif].len > 0
    regularLoaded = (fwRegular, fsNormal) in gFontTable[fcSansSerif]
  if fcMonospace in gFontTable:
    monoLoaded = gFontTable[fcMonospace].len > 0

  if regularLoaded:
    let regularFont = gFontTable[fcSansSerif][(fwRegular, fsNormal)]
    let regularName = gFontHandleToName.getOrDefault(regularFont, "unknown")
    info "Fonts ready", regular = regularName
  else:
    warn "Fonts ready but Regular not loaded!"
  debug "Font loading details", sans = sansLoaded, mono = monoLoaded, variants = (if fcSansSerif in gFontTable: gFontTable[fcSansSerif].len else: 0), regularLoaded = regularLoaded

# Dynamic font loading
proc CTFontCreateForString*(currentFont: CTFont, str: CFString, range: CFRange): CTFont {.importc.}

proc loadDynamicFont*(vg: NVGContext, ctFont: CTFont): Font =
  ## Dynamically load font using PostScript name as unique identifier
  let psName = ctFont.copyPostScriptName()
  if psName.isNil:
    raise newException(FontError, "Failed to get PostScript name for dynamic font")
  defer: psName.release()
  
  let fontName = $psName
  
  # Check if already loaded
  if fontName in gFontNameToHandle:
    return gFontNameToHandle[fontName]
  
  # Load font
  result = loadFontFromFile(vg, ctFont, fontName)
  
  # Cache
  gFontNameToHandle[fontName] = result
  gFontHandleToName[result] = fontName
  gDynamicFontsLoaded[fontName] = true
  
  debug "Dynamic font loaded", font = fontName

proc CTFontCreateWithName*(name: CFString, size: cdouble, matrix: pointer): CTFont {.importc.}

# Cache for base CTFonts to avoid creating them every time
var gBaseCTFontCache: TableRef[string, CTFont] = newTable[string, CTFont]()

proc getBaseCTFont(fontName: string): CTFont =
  ## Get cached CTFont for a base font, creating and caching if necessary
  if fontName in gBaseCTFontCache:
    return gBaseCTFontCache[fontName]
  
  # Create CTFont
  if fontName.startsWith("."):
    result = CTFontCreateUIFontForLanguage(kCTFontUIFontSystem, 12.0, nil)
  else:
    let fontNameCF = CFStringCreate(fontName)
    if fontNameCF.isNil:
      return nil
    defer: fontNameCF.release()
    result = CTFontCreateWithName(fontNameCF, 12.0, nil)
  
  # Cache it (we retain it by not releasing - cache lives for app lifetime)
  if not result.isNil:
    gBaseCTFontCache[fontName] = result

proc hasNonAsciiFast(s: string): bool {.inline.} =
  ## Fast check for non-ASCII characters without rune iteration
  for c in s:
    if c.uint8 > 127:
      return true
  return false

proc getFontForString*(vg: NVGContext, baseFont: Font, str: string): Font =
  ## Get font that can render this string, dynamically loading if necessary
  ## Uses CTFontCreateForString to find the best font for the given string
  
  # Get baseFont's font name
  if baseFont notin gFontHandleToName:
    return baseFont
  
  let baseFontName = gFontHandleToName[baseFont]
  
  # Fast path: if string is all ASCII, base font should work
  if not hasNonAsciiFast(str):
    return baseFont
  
  # Create CFString from input
  let cfStr = CFStringCreate(str)
  if cfStr.isNil:
    return baseFont
  defer: cfStr.release()
  
  # Get baseFont's CTFont from cache (no release needed - cached)
  let baseCTFont = getBaseCTFont(baseFontName)
  if baseCTFont.isNil:
    return baseFont
  
  # Use CTFontCreateForString to find suitable font
  let ctFont = CTFontCreateForString(baseCTFont, cfStr, CFRangeMake(0, str.runeLen.cint))
  if ctFont.isNil:
    return baseFont
  defer: ctFont.release()
  
  # Get found font name
  let foundPsName = ctFont.copyPostScriptName()
  if foundPsName.isNil:
    return baseFont
  defer: foundPsName.release()
  
  let foundFontName = $foundPsName
  
  # If CTFontCreateForString returned the same font name, the base font should
  # already have the correct glyphs for this string. Just return the base font.
  if foundFontName == baseFontName:
    return baseFont
  
  # Dynamically load and return the suggested font
  try:
    result = loadDynamicFont(vg, ctFont)
  except FontError:
    result = baseFont
