## Icons Module
## Provides pure drawing functions for UI icons using NanoVG
## All functions take NVGContext as first parameter for easy composition

import nanovg
import math

export nanovg.Color

proc drawSpinner*(vg: NVGContext, x, y, size: float32, progress: float32, col: Color) =
  ## Draw a loading spinner at position (x, y)
  let numSegments = 8
  let angleStep = 2.0 * PI / numSegments.float32
  let radius = size / 2.0

  for i in 0..<numSegments:
    let angle = i.float32 * angleStep + progress * 2.0 * PI
    let alpha = (i.float32 / numSegments.float32) * col.a
    let segmentColor = Color(r: col.r, g: col.g, b: col.b, a: alpha)

    let sx = x + radius + cos(angle) * radius * 0.7
    let sy = y + radius + sin(angle) * radius * 0.7

    vg.fillColor(segmentColor)
    vg.beginPath()
    vg.circle(sx, sy, size * 0.08)
    vg.fill()

proc drawTrashIcon*(vg: NVGContext, x, y, size: float32, col: Color) =
  ## Draw a trash can icon at position (x, y)
  let s = size / 24.0  # Scale factor based on 24x24 viewBox

  vg.strokeColor(col)
  vg.strokeWidth(1.5 * s)
  vg.lineCap(lcjRound)
  vg.lineJoin(lcjRound)

  # Trash can body
  vg.beginPath()
  vg.moveTo(x + 6*s, y + 8*s)
  vg.lineTo(x + 6*s, y + 20*s)
  vg.lineTo(x + 18*s, y + 20*s)
  vg.lineTo(x + 18*s, y + 8*s)
  vg.stroke()

  # Trash can lid
  vg.beginPath()
  vg.moveTo(x + 4*s, y + 6*s)
  vg.lineTo(x + 20*s, y + 6*s)
  vg.stroke()

  # Lid handle
  vg.beginPath()
  vg.moveTo(x + 10*s, y + 6*s)
  vg.lineTo(x + 10*s, y + 3*s)
  vg.lineTo(x + 14*s, y + 3*s)
  vg.lineTo(x + 14*s, y + 6*s)
  vg.stroke()

  # Vertical lines inside
  vg.beginPath()
  vg.moveTo(x + 10*s, y + 10*s)
  vg.lineTo(x + 10*s, y + 16*s)
  vg.moveTo(x + 14*s, y + 10*s)
  vg.lineTo(x + 14*s, y + 16*s)
  vg.stroke()

proc drawInfoIcon*(vg: NVGContext, x, y, size: float32, col: Color) =
  ## Draw an info icon (circle with 'i') at position (x, y)
  let s = size / 24.0  # Scale factor based on 24x24 viewBox
  let centerX = x + 12*s
  let centerY = y + 12*s
  let radius = 10*s

  # Draw circle
  vg.strokeColor(col)
  vg.strokeWidth(1.5 * s)
  vg.beginPath()
  vg.circle(centerX, centerY, radius)
  vg.stroke()

  # Draw 'i' dot
  vg.fillColor(col)
  vg.beginPath()
  vg.circle(centerX, centerY - 4*s, 1.5*s)
  vg.fill()

  # Draw 'i' stem
  vg.fillColor(col)
  vg.beginPath()
  vg.rect(centerX - 1*s, centerY - 1*s, 2*s, 6*s)
  vg.fill()

proc drawChevronDown*(vg: NVGContext, x, y, size: float32, col: Color) =
  ## Draw a chevron down icon at position (x, y)
  let s = size / 24.0

  vg.strokeColor(col)
  vg.strokeWidth(2.0 * s)
  vg.lineCap(lcjRound)
  vg.lineJoin(lcjRound)

  vg.beginPath()
  vg.moveTo(x + 6*s, y + 9*s)
  vg.lineTo(x + 12*s, y + 15*s)
  vg.lineTo(x + 18*s, y + 9*s)
  vg.stroke()

proc drawChevronRight*(vg: NVGContext, x, y, size: float32, col: Color) =
  ## Draw a chevron right icon at position (x, y)
  let s = size / 24.0

  vg.strokeColor(col)
  vg.strokeWidth(2.0 * s)
  vg.lineCap(lcjRound)
  vg.lineJoin(lcjRound)

  vg.beginPath()
  vg.moveTo(x + 9*s, y + 6*s)
  vg.lineTo(x + 15*s, y + 12*s)
  vg.lineTo(x + 9*s, y + 18*s)
  vg.stroke()
