## UI Widgets Module
## Provides reusable UI widget drawing functions using NanoVG
## All functions take NVGContext as first parameter for easy composition

import nanovg, nanovg/wrapper as nvgWrapper
import ./theme
import ./ui_constants
import ./rendering
import ./fonts

export nanovg.Color

type
  DialogConfig* = object
    width*, height*: float32
    animSpeed*: float32
    title*: string
    primaryBtnText*: string
    secondaryBtnText*: string  # Empty = single button dialog
    
  ButtonState* = enum bsNormal, bsHover, bsPressed

proc drawStyledButton*(vg: NVGContext, x, y, w, h: float32, text: string, hovered: bool,
                       theme: ThemeColors, scale: float32, cornerRadius: float32 = 6.0,
                       customBgColor: Color = Color(r: 0, g: 0, b: 0, a: 0)) =
  ## Draw a macOS-style styled button with gradient and proper states
  ## If customBgColor is provided (a > 0), use it instead of theme.accent
  let bgColor = if customBgColor.a > 0:
      customBgColor
    elif hovered:
      theme.accentHover
    else:
      theme.accent
  let textColor = theme.buttonText

  let r = cornerRadius * scale

  # Draw button shadow for depth (slightly larger, softer)
  vg.beginPath()
  vg.roundedRect(x, y + 2.0 * scale, w, h, r)
  vg.fillColor(Color(r: 0, g: 0, b: 0, a: 0.08))
  vg.fill()

  # Draw button background with gradient
  vg.beginPath()
  vg.roundedRect(x, y, w, h, r)
  let bgPaint = vg.linearGradient(x, y, x, y + h,
    Color(r: bgColor.r, g: bgColor.g, b: bgColor.b, a: 1.0),
    Color(r: bgColor.r * 0.9, g: bgColor.g * 0.9, b: bgColor.b * 0.9, a: 1.0))
  vg.fillPaint(bgPaint)
  vg.fill()

  # Draw top highlight line for 3D effect (full width, same corner radius)
  vg.beginPath()
  vg.roundedRect(x, y, w, h * 0.55, r)
  vg.fillColor(Color(r: 1.0, g: 1.0, b: 1.0, a: 0.1))
  vg.fill()

  # Draw subtle border (inset by 0.5px for crisp edges)
  vg.beginPath()
  vg.roundedRect(x + 0.5, y + 0.5, w - 1.0, h - 1.0, r - 0.5)
  vg.strokeColor(Color(r: 0, g: 0, b: 0, a: 0.1))
  vg.strokeWidth(1.0)
  vg.stroke()

  # Draw button text
  vg.fontSize(13 * scale)
  vg.fontFace(getDefaultFont())
  vg.fillColor(textColor)
  vg.textAlign(haCenter, vaMiddle)
  discard vg.text(x + w / 2, y + h / 2 + 1.0 * scale, text)

proc drawDialogFrame*(vg: NVGContext, screenW, screenH, x, y, w, h, scale, bgAlpha: float32,
                     theme: ThemeColors) =
  ## Draw common dialog frame: overlay, background, border, ribbon banner
  ## Content should be drawn by the caller after this
  
  # Draw full-screen overlay (multiply overlay alpha with animation progress)
  let overlayColor = Color(
    r: theme.overlay.r,
    g: theme.overlay.g,
    b: theme.overlay.b,
    a: theme.overlay.a * bgAlpha
  )
  drawRect(vg, 0, 0, screenW, screenH, overlayColor)
  
  # Draw dialog background
  drawRoundedRect(vg, x, y, w, h, DialogCornerRadius * scale, theme.dialogBackground.withAlpha(bgAlpha))
  
  # Draw dialog border
  drawRoundedRectStroke(vg, x, y, w, h, DialogCornerRadius * scale, DialogBorderWidth * scale, 
                        theme.separator.withAlpha(bgAlpha))
  
  # Draw ribbon banner
  let bannerHeight = InfoDialogBannerHeight * scale
  let bannerY = y + InfoDialogBannerYOffset * scale
  let notchSize = InfoDialogNotchSize * scale
  drawRibbonBanner(vg, x, bannerY, w, bannerHeight, notchSize, InfoDialogRibbonRightOffset * scale, 
                   scale, theme.accent, bgAlpha)

proc drawDialogTitle*(vg: NVGContext, x, y, w, bannerHeight, scale, bgAlpha: float32,
                     theme: ThemeColors, title: string, font: nvgWrapper.Font) =
  ## Draw dialog title centered on the ribbon banner
  let titleColor = theme.buttonText.withAlpha(bgAlpha)
  let titleX = x + (w - InfoDialogRibbonRightOffset * scale) / 2
  let titleY = y + bannerHeight / 2 + scale
  drawTextCentered(vg, titleX, titleY, title, InfoDialogTitleFontSize * scale, titleColor, font)

proc drawDialog*(
    vg: NVGContext,
    screenW, screenH, scale: float32,
    theme: ThemeColors,
    cfg: DialogConfig,
    anim: float32,
    hoverPrimary, hoverSecondary: bool,
    primaryBtn, secondaryBtn: var tuple[x, y, w, h: float32],
    hasSecondary: bool,
    drawContent: proc(vg: NVGContext, x, y, w, h, alpha, scale: float32)
  ) =
  ## Unified dialog drawing - handles frame, title, buttons. Content drawn via callback.
  
  let dialogW = cfg.width * scale
  let dialogH = cfg.height * scale
  let dialogX = (screenW - dialogW) / 2
  let dialogY = (screenH - dialogH) / 2
  let bgAlpha = anim
  
  # Draw frame and title
  drawDialogFrame(vg, screenW, screenH, dialogX, dialogY, dialogW, dialogH, scale, bgAlpha, theme)
  
  let bannerHeight = InfoDialogBannerHeight * scale
  let bannerY = dialogY + InfoDialogBannerYOffset * scale
  drawDialogTitle(vg, dialogX, bannerY, dialogW, bannerHeight, scale, bgAlpha, theme, cfg.title, getDefaultFont(fwBold))
  
  # Draw custom content
  let contentY = bannerY + bannerHeight
  let contentH = dialogH - bannerHeight - ConfirmDialogButtonYOffset * scale - ConfirmDialogButtonHeight * scale
  drawContent(vg, dialogX + InfoDialogContentPadding * scale, contentY, 
              dialogW - InfoDialogContentPadding * 2 * scale, contentH, bgAlpha, scale)
  
  # Draw buttons
  let btnW = ConfirmDialogButtonWidth * scale
  let btnH = ConfirmDialogButtonHeight * scale
  let btnY = dialogY + dialogH - btnH - ConfirmDialogButtonYOffset * scale
  
  if hasSecondary and cfg.secondaryBtnText.len > 0:
    # Two-button dialog
    let btnSpacing = ConfirmDialogButtonSpacing * scale
    let totalBtnW = btnW * 2 + btnSpacing
    let btnStartX = dialogX + (dialogW - totalBtnW) / 2
    let cancelBtnX = btnStartX
    let confirmBtnX = btnStartX + btnW + btnSpacing
    
    secondaryBtn = (cancelBtnX, btnY, btnW, btnH)
    primaryBtn = (confirmBtnX, btnY, btnW, btnH)
    
    let cancelBgColor = if hoverSecondary: theme.buttonSecondaryHover else: theme.buttonSecondary
    drawStyledButton(vg, cancelBtnX, btnY, btnW, btnH, cfg.secondaryBtnText,
                     hoverSecondary, theme, scale, 6.0, cancelBgColor)
    
    let confirmBgColor = if hoverPrimary: theme.buttonDestructiveHover else: theme.buttonDestructive
    drawStyledButton(vg, confirmBtnX, btnY, btnW, btnH, cfg.primaryBtnText,
                     hoverPrimary, theme, scale, 6.0, confirmBgColor)
  else:
    # Single button dialog
    let btnX = dialogX + (dialogW - btnW) / 2
    primaryBtn = (btnX, btnY, btnW, btnH)
    
    let btnBgColor = if hoverPrimary: theme.buttonSecondaryHover else: theme.buttonSecondary
    drawStyledButton(vg, btnX, btnY, btnW, btnH, cfg.primaryBtnText,
                     hoverPrimary, theme, scale, 6.0, btnBgColor)
