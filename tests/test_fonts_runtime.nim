## Font system runtime tests
## Tests actual font loading with NanoVG

import std/[tables, strutils, os]
import nglfw
import nanovg
import ../src/devcleaner/[fonts, glfw_nanovg]

proc main() =
  echo ""
  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║           Font System Runtime Tests                          ║"
  echo "╚══════════════════════════════════════════════════════════════╝"
  echo ""

  # Initialize GLFW and NanoVG
  discard init()

  defaultWindowHints()
  windowHint(CLIENT_API, OPENGL_API)
  windowHint(CONTEXT_VERSION_MAJOR, 3)
  windowHint(CONTEXT_VERSION_MINOR, 2)
  windowHint(OPENGL_PROFILE, OPENGL_CORE_PROFILE)
  windowHint(OPENGL_FORWARD_COMPAT, 1)
  windowHint(VISIBLE, 0)

  let window = createWindow(100, 100, "Font Test", nil, nil)
  if window == nil:
    echo "Failed to create window"
    terminate()
    return

  makeContextCurrent(window)

  let vg = nanovg.nvgCreateContext({nifAntialias, nifStencilStrokes})
  if vg == nil:
    echo "❌ Failed to create NVG context"
    destroyWindow(window)
    terminate()
    return

  echo "✓ NanoVG context created"
  echo ""

  # Load fonts
  echo "=== Loading fonts ==="
  loadFonts(vg)
  echo ""

  # Check loaded fonts
  echo "=== Loaded font variants ==="
  if fcSansSerif in gFontTable:
    echo "fcSansSerif has " & $gFontTable[fcSansSerif].len & " variants:"
    for key, font in gFontTable[fcSansSerif]:
      let (weight, style) = key
      let fontName = gFontHandleToName.getOrDefault(font, "unknown")
      echo "  (" & $weight & ", " & $style & ") -> handle " & $font.int & " -> " & fontName
  else:
    echo "❌ fcSansSerif not loaded!"

  echo ""

  # Test getDefaultFont
  echo "=== Testing getDefaultFont ==="
  try:
    let defaultFont = getDefaultFont()
    let defaultFontName = gFontHandleToName.getOrDefault(defaultFont, "unknown")
    echo "getDefaultFont() -> handle " & $defaultFont.int & " -> " & defaultFontName

    # Check if it's actually Regular
    if defaultFontName.contains("Italic"):
      echo "❌ WARNING: Default font is Italic!"
    elif defaultFontName.contains("Regular") or defaultFontName == "inter-fwRegular-fsNormal":
      echo "✓ Default font is Regular"
    else:
      echo "? Default font name: " & defaultFontName
  except FontError as e:
    echo "❌ getDefaultFont failed: " & e.msg

  echo ""

  # Test getFont with specific weight/style
  echo "=== Testing getFont with specific weight/style ==="
  try:
    let regularNormal = getFont(fcSansSerif, fwRegular, fsNormal)
    let regularNormalName = gFontHandleToName.getOrDefault(regularNormal, "unknown")
    echo "getFont(fcSansSerif, fwRegular, fsNormal) -> " & regularNormalName

    let regularItalic = getFont(fcSansSerif, fwRegular, fsItalic)
    let regularItalicName = gFontHandleToName.getOrDefault(regularItalic, "unknown")
    echo "getFont(fcSansSerif, fwRegular, fsItalic) -> " & regularItalicName

    let boldNormal = getFont(fcSansSerif, fwBold, fsNormal)
    let boldNormalName = gFontHandleToName.getOrDefault(boldNormal, "unknown")
    echo "getFont(fcSansSerif, fwBold, fsNormal) -> " & boldNormalName

    let boldItalic = getFont(fcSansSerif, fwBold, fsItalic)
    let boldItalicName = gFontHandleToName.getOrDefault(boldItalic, "unknown")
    echo "getFont(fcSansSerif, fwBold, fsItalic) -> " & boldItalicName

    # Verify they're different
    if regularNormal == regularItalic:
      echo "❌ WARNING: Regular Normal and Regular Italic have the same handle!"
    else:
      echo "✓ Regular Normal and Regular Italic have different handles"

    if boldNormal == boldItalic:
      echo "❌ WARNING: Bold Normal and Bold Italic have the same handle!"
    else:
      echo "✓ Bold Normal and Bold Italic have different handles"

  except FontError as e:
    echo "❌ getFont failed: " & e.msg

  echo ""

  # Cleanup
  nanovg.nvgDeleteContext(vg)
  destroyWindow(window)
  terminate()

  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║           Runtime tests complete                             ║"
  echo "╚══════════════════════════════════════════════════════════════╝"
  echo ""

when isMainModule:
  main()
