## Theme module for DevCleaner
## Handles dark mode detection and color theming using YAML config files

import std/[strutils, os]
import yanyl
import nanovg
import chroma except Color
import darwin/objc/runtime
import darwin/[app_kit, foundation]
import darwin/app_kit/nsappearance

proc isDarkMode*(): bool =
  ## Detect if macOS dark mode is enabled
  let appearance = NSAppearance.currentAppearance()
  if appearance.isNil:
    return false
  let name = appearance.name()
  if name.isNil:
    return false
  # Check if appearance name contains "Dark"
  let nameStr = $name
  return nameStr.contains("Dark")

# Theme color definitions
type
  ThemeColors* = object
    # Background colors
    background*: Color
    listBackground*: Color
    rowBackground*: Color
    rowBackgroundAlt*: Color
    dialogBackground*: Color
    # Button colors
    buttonBackground*: Color
    buttonBackgroundHover*: Color
    buttonBackgroundPressed*: Color
    buttonBackgroundDisabled*: Color
    buttonSecondary*: Color
    buttonSecondaryHover*: Color
    buttonDestructive*: Color
    buttonDestructiveHover*: Color
    buttonText*: Color
    # Text colors
    textPrimary*: Color
    textSecondary*: Color
    textMuted*: Color
    textInverse*: Color
    textDisabled*: Color
    subtitle*: Color
    # Border and separator colors
    border*: Color
    separator*: Color
    # Accent colors
    accent*: Color
    accentHover*: Color
    accentPressed*: Color
    # Overlay
    overlay*: Color
    # Status colors
    success*: Color
    warning*: Color
    error*: Color
    info*: Color

# Custom YAML parsing for Color type
proc ofYaml(n: YNode; t: typedesc[Color]): Color =
  let c = parseHtmlColor(n.strVal.strip())
  Color(r: c.r.float32, g: c.g.float32, b: c.b.float32, a: c.a.float32)

proc toYaml(c: Color): YNode =
  let r = (c.r * 255).int
  let g = (c.g * 255).int
  let b = (c.b * 255).int
  let a = c.a
  
  if a < 1.0:
    # Use rgba() format for colors with alpha
    newYString("rgba(" & $r & ", " & $g & ", " & $b & ", " & $a & ")")
  else:
    # Use hex format for opaque colors
    newYString("#" & r.toHex(2) & g.toHex(2) & b.toHex(2))

deriveYaml ThemeColors

# Theme configuration
type
  ThemeConfig* = object
    lightTheme*: ThemeColors
    darkTheme*: ThemeColors

# Custom YAML parsing for ThemeConfig
proc ofYaml(n: YNode; t: typedesc[ThemeConfig]): ThemeConfig =
  if n.kind != ynMap:
    raise newException(ValueError, "Expected YAML mapping for ThemeConfig")
  
  # Parse lightTheme
  let lightNode = n.get("lightTheme")
  if lightNode.kind != ynNil:
    result.lightTheme = ofYaml(lightNode, ThemeColors)
  
  # Parse darkTheme
  let darkNode = n.get("darkTheme")
  if darkNode.kind != ynNil:
    result.darkTheme = ofYaml(darkNode, ThemeColors)

const ColorsYamlContent = staticRead(os.parentDir(os.parentDir(os.parentDir(currentSourcePath()))) / "config" / "colors.yaml")

var themeConfig*: ThemeConfig
var currentThemeColors*: ptr ThemeColors

proc initTheme*() =
  ## Initialize theme from YAML config
  themeConfig = ofYamlStr(ColorsYamlContent, ThemeConfig)
  if isDarkMode():
    currentThemeColors = addr themeConfig.darkTheme
  else:
    currentThemeColors = addr themeConfig.lightTheme

initTheme()

proc updateThemeFromSystem*() =
  ## Update theme based on system dark mode
  if isDarkMode():
    currentThemeColors = addr themeConfig.darkTheme
  else:
    currentThemeColors = addr themeConfig.lightTheme

proc getCurrentTheme*(): ThemeColors =
  ## Get the appropriate theme based on system dark mode setting

  result = currentThemeColors[]
