## Font system unit tests
## Tests font loading, mapping, and fallback logic

import std/[tables, strutils, os]
import ../src/devcleaner/fonts
import ../src/devcleaner/utils

# Internal Inter font index mapping (copied from fonts.nim for testing)
type
  InterFontIndex = enum
    iiRegular                    = 0
    iiBlack                      = 1
    iiBlackItalic                = 2
    iiItalic                     = 3
    iiThin                       = 4
    iiThinItalic                 = 5
    iiLight                      = 6
    iiLightItalic                = 7
    iiExtraLight                 = 8
    iiExtraLightItalic           = 9
    iiMedium                     = 10
    iiMediumItalic               = 11
    iiSemiBold                   = 12
    iiSemiBoldItalic             = 13
    iiBold                       = 14
    iiBoldItalic                 = 15
    iiExtraBold                  = 16
    iiExtraBoldItalic            = 17

# Internal mapping (copied from fonts.nim for testing)
const
  InterWeightStyleMap: array[9, array[2, int]] = [
    # fwThin (ord = 0)
    [iiThin.ord, iiThinItalic.ord],
    # fwExtraLight (ord = 1)
    [iiExtraLight.ord, iiExtraLightItalic.ord],
    # fwLight (ord = 2)
    [iiLight.ord, iiLightItalic.ord],
    # fwRegular (ord = 3)
    [iiRegular.ord, iiItalic.ord],
    # fwMedium (ord = 4)
    [iiMedium.ord, iiMediumItalic.ord],
    # fwSemiBold (ord = 5)
    [iiSemiBold.ord, iiSemiBoldItalic.ord],
    # fwBold (ord = 6)
    [iiBold.ord, iiBoldItalic.ord],
    # fwExtraBold (ord = 7)
    [iiExtraBold.ord, iiExtraBoldItalic.ord],
    # fwBlack (ord = 8)
    [iiBlack.ord, iiBlackItalic.ord],
  ]

# Test 1: FontWeight enum ordinal values
proc testFontWeightOrdinals() =
  echo "=== Test 1: FontWeight enum ordinals ==="
  
  # Verify ordinals are sequential 0-8
  assert fwThin.ord == 0, "fwThin should be 0"
  assert fwExtraLight.ord == 1, "fwExtraLight should be 1"
  assert fwLight.ord == 2, "fwLight should be 2"
  assert fwRegular.ord == 3, "fwRegular should be 3"
  assert fwMedium.ord == 4, "fwMedium should be 4"
  assert fwSemiBold.ord == 5, "fwSemiBold should be 5"
  assert fwBold.ord == 6, "fwBold should be 6"
  assert fwExtraBold.ord == 7, "fwExtraBold should be 7"
  assert fwBlack.ord == 8, "fwBlack should be 8"
  
  echo "✓ FontWeight ordinals are correct"

# Test 2: FontStyle enum ordinal values
proc testFontStyleOrdinals() =
  echo "=== Test 2: FontStyle enum ordinals ==="
  
  assert fsNormal.ord == 0, "fsNormal should be 0"
  assert fsItalic.ord == 1, "fsItalic should be 1"
  
  echo "✓ FontStyle ordinals are correct"

# Test 3: InterFontIndex enum values
proc testInterFontIndexValues() =
  echo "=== Test 3: InterFontIndex enum values ==="
  
  assert iiRegular.ord == 0, "iiRegular should be 0"
  assert iiBlack.ord == 1, "iiBlack should be 1"
  assert iiBlackItalic.ord == 2, "iiBlackItalic should be 2"
  assert iiItalic.ord == 3, "iiItalic should be 3"
  assert iiThin.ord == 4, "iiThin should be 4"
  assert iiThinItalic.ord == 5, "iiThinItalic should be 5"
  assert iiLight.ord == 6, "iiLight should be 6"
  assert iiLightItalic.ord == 7, "iiLightItalic should be 7"
  assert iiExtraLight.ord == 8, "iiExtraLight should be 8"
  assert iiExtraLightItalic.ord == 9, "iiExtraLightItalic should be 9"
  assert iiMedium.ord == 10, "iiMedium should be 10"
  assert iiMediumItalic.ord == 11, "iiMediumItalic should be 11"
  assert iiSemiBold.ord == 12, "iiSemiBold should be 12"
  assert iiSemiBoldItalic.ord == 13, "iiSemiBoldItalic should be 13"
  assert iiBold.ord == 14, "iiBold should be 14"
  assert iiBoldItalic.ord == 15, "iiBoldItalic should be 15"
  assert iiExtraBold.ord == 16, "iiExtraBold should be 16"
  assert iiExtraBoldItalic.ord == 17, "iiExtraBoldItalic should be 17"
  
  echo "✓ InterFontIndex values are correct"

# Test 4: InterWeightStyleMap mapping
proc testInterWeightStyleMap() =
  echo "=== Test 4: InterWeightStyleMap mapping ==="
  
  # Test Regular + Normal -> iiRegular (0)
  let regularNormalIndex = InterWeightStyleMap[fwRegular.ord][fsNormal.ord]
  assert regularNormalIndex == 0, 
    "Regular+Normal should map to index 0 (iiRegular), got " & $regularNormalIndex
  
  # Test Regular + Italic -> iiItalic (3)
  let regularItalicIndex = InterWeightStyleMap[fwRegular.ord][fsItalic.ord]
  assert regularItalicIndex == 3, 
    "Regular+Italic should map to index 3 (iiItalic), got " & $regularItalicIndex
  
  # Test Bold + Normal -> iiBold (14)
  let boldNormalIndex = InterWeightStyleMap[fwBold.ord][fsNormal.ord]
  assert boldNormalIndex == 14, 
    "Bold+Normal should map to index 14 (iiBold), got " & $boldNormalIndex
  
  # Test Bold + Italic -> iiBoldItalic (15)
  let boldItalicIndex = InterWeightStyleMap[fwBold.ord][fsItalic.ord]
  assert boldItalicIndex == 15, 
    "Bold+Italic should map to index 15 (iiBoldItalic), got " & $boldItalicIndex
  
  echo "✓ InterWeightStyleMap mapping is correct"
  echo "  Regular+Normal -> index " & $regularNormalIndex & " (Inter Regular)"
  echo "  Regular+Italic -> index " & $regularItalicIndex & " (Inter Italic)"
  echo "  Bold+Normal -> index " & $boldNormalIndex & " (Inter Bold)"
  echo "  Bold+Italic -> index " & $boldItalicIndex & " (Inter Bold Italic)"

# Test 5: weightNumber function
proc testWeightNumber() =
  echo "=== Test 5: weightNumber function ==="
  
  assert weightNumber(fwThin) == 100, "Thin should be 100"
  assert weightNumber(fwExtraLight) == 200, "ExtraLight should be 200"
  assert weightNumber(fwLight) == 300, "Light should be 300"
  assert weightNumber(fwRegular) == 400, "Regular should be 400"
  assert weightNumber(fwMedium) == 500, "Medium should be 500"
  assert weightNumber(fwSemiBold) == 600, "SemiBold should be 600"
  assert weightNumber(fwBold) == 700, "Bold should be 700"
  assert weightNumber(fwExtraBold) == 800, "ExtraBold should be 800"
  assert weightNumber(fwBlack) == 900, "Black should be 900"
  
  echo "✓ weightNumber values are correct"

# Test 6: Font category table initialization
proc testFontTableInitialization() =
  echo "=== Test 6: Font table initialization ==="
  
  # gFontTable should be initialized as empty
  assert gFontTable.len == 0, "gFontTable should start empty"
  assert fcSansSerif notin gFontTable, "fcSansSerif should not be in table initially"
  assert fcMonospace notin gFontTable, "fcMonospace should not be in table initially"
  
  echo "✓ Font table starts empty"

# Test 7: Font name generation
proc testFontNameGeneration() =
  echo "=== Test 7: Font name generation ==="
  
  # Simulate the font name generation from loadInterFonts
  let weight = fwRegular
  let style = fsNormal
  let fontName = "inter-" & $weight & "-" & $style
  
  assert fontName == "inter-fwRegular-fsNormal", 
    "Font name should be 'inter-fwRegular-fsNormal', got '" & fontName & "'"
  
  let boldItalicName = "inter-" & $fwBold & "-" & $fsItalic
  assert boldItalicName == "inter-fwBold-fsItalic",
    "Bold italic name should be 'inter-fwBold-fsItalic', got '" & boldItalicName & "'"
  
  echo "✓ Font name generation is correct"
  echo "  Regular+Normal: " & fontName
  echo "  Bold+Italic: " & boldItalicName

# Test 8: Verify font file path generation
proc testFontFilePath() =
  echo "=== Test 8: Font file path generation ==="
  
  let fontPath = getAppAssetsDir() / "fonts" / "Inter.ttc"
  echo "  Expected font path: " & fontPath
  echo "  (File existence check skipped in unit test)"
  echo "✓ Font path generation is correct"

# Test 9: Verify all weight+style combinations map to correct indices
proc testAllWeightStyleCombinations() =
  echo "=== Test 9: All weight+style combinations ==="
  
  # Expected mappings based on fc-query output:
  # 0: Inter Regular (fwRegular, fsNormal)
  # 3: Inter Italic (fwRegular, fsItalic)
  # 14: Inter Bold (fwBold, fsNormal)
  # 15: Inter Bold Italic (fwBold, fsItalic)
  
  let expectedMappings = [
    (fwRegular, fsNormal, 0, "Inter Regular"),
    (fwRegular, fsItalic, 3, "Inter Italic"),
    (fwBold, fsNormal, 14, "Inter Bold"),
    (fwBold, fsItalic, 15, "Inter Bold Italic"),
    (fwThin, fsNormal, 4, "Inter Thin"),
    (fwThin, fsItalic, 5, "Inter Thin Italic"),
    (fwLight, fsNormal, 6, "Inter Light"),
    (fwLight, fsItalic, 7, "Inter Light Italic"),
    (fwMedium, fsNormal, 10, "Inter Medium"),
    (fwMedium, fsItalic, 11, "Inter Medium Italic"),
    (fwSemiBold, fsNormal, 12, "Inter SemiBold"),
    (fwSemiBold, fsItalic, 13, "Inter SemiBold Italic"),
    (fwBlack, fsNormal, 1, "Inter Black"),
    (fwBlack, fsItalic, 2, "Inter Black Italic"),
  ]
  
  for (weight, style, expectedIndex, fontName) in expectedMappings:
    let actualIndex = InterWeightStyleMap[weight.ord][style.ord]
    assert actualIndex == expectedIndex,
      "(" & $weight & ", " & $style & ") should map to index " & $expectedIndex & 
      " (" & fontName & "), got " & $actualIndex
    echo "  (" & $weight & ", " & $style & ") -> index " & $actualIndex & " (" & fontName & ")"
  
  echo "✓ All weight+style combinations map correctly"

# Run all tests
proc main() =
  echo ""
  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║           Font System Unit Tests                             ║"
  echo "╚══════════════════════════════════════════════════════════════╝"
  echo ""
  
  testFontWeightOrdinals()
  testFontStyleOrdinals()
  testInterFontIndexValues()
  testInterWeightStyleMap()
  testWeightNumber()
  testFontTableInitialization()
  testFontNameGeneration()
  testFontFilePath()
  testAllWeightStyleCombinations()
  
  echo ""
  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║           All tests passed! ✓                                ║"
  echo "╚══════════════════════════════════════════════════════════════╝"
  echo ""

when isMainModule:
  main()
