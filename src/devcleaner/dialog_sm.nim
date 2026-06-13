## Dialog State Machine
## Manages dialog lifecycle with explicit state transitions
## Compatible with existing Dialog interface

# Dialog states - compatible with existing code
type DialogState* = enum
  dsHidden = 0      # Dialog not shown (compatible)
  dsOpening = 1     # Opening animation in progress
  dsVisible = 2     # Fully visible, accepting input (compatible)
  dsProcessing = 3  # User action confirmed, processing
  dsClosing = 4     # Closing animation in progress (compatible)

# Dialog events
type DialogEvent* = enum
  deShow = 0           # Show dialog request
  deOpenComplete = 1   # Opening animation complete
  deConfirm = 2        # User confirmed action
  deCancel = 3         # User cancelled
  deProcessComplete = 4 # Processing complete
  deCloseComplete = 5  # Closing animation complete
  deForceHide = 6      # Force immediate hide

# Transition matrix: state x event -> new state (-1 = invalid)
const TransitionMatrix: array[5, array[7, int16]] = [
  # dsHidden: show -> opening, forceHide -> hidden
  [1'i16, -1, -1, -1, -1, -1, 0],
  # dsOpening: openComplete -> visible, forceHide -> hidden
  [-1, 2, -1, -1, -1, -1, 0],
  # dsVisible: confirm -> processing, cancel -> closing, forceHide -> hidden
  [-1, -1, 3, 4, -1, -1, 0],
  # dsProcessing: processComplete -> closing, forceHide -> hidden
  [-1, -1, -1, -1, 4, -1, 0],
  # dsClosing: closeComplete -> hidden, forceHide -> hidden
  [-1, -1, -1, -1, -1, 0, 0]
]

# Dialog type with state machine
type Dialog* = object
  # State
  state*: DialogState
  anim*: float32
  # Content
  title*: string
  message*: string
  itemPath*: string
  itemSize*: int64
  appIndex*: int
  pathIndex*: int
  # Info dialog content
  projectPath*: string
  description*: string
  # Button layout
  primaryBtn*: tuple[x, y, w, h: float32]
  secondaryBtn*: tuple[x, y, w, h: float32]
  hasSecondary*: bool
  # Interaction
  hoverPrimary*: bool
  hoverSecondary*: bool
  clickedPrimary*: bool

# Alias for compatibility
type DialogSM* = Dialog

# Helper to handle event
proc handleEvent(d: var DialogSM, evt: DialogEvent): bool =
  let fromState = d.state.ord
  let toState = TransitionMatrix[fromState][evt.ord]
  if toState < 0:
    return false
  d.state = DialogState(toState)
  return true

# Public API - compatible with existing code

proc init*(d: var DialogSM) =
  d.state = dsHidden
  d.anim = 0.0
  d.appIndex = -1
  d.pathIndex = -1
  d.clickedPrimary = false
  d.hasSecondary = true

proc showDialog*(d: var DialogSM) =
  ## Show dialog - compatible with existing code
  discard d.handleEvent(deShow)
  d.clickedPrimary = false

proc close*(d: var DialogSM) =
  ## Close dialog - compatible with existing code
  if d.state == dsVisible:
    discard d.handleEvent(deCancel)
  elif d.state == dsProcessing:
    discard d.handleEvent(deProcessComplete)

proc forceHide*(d: var DialogSM) =
  ## Force immediate hide
  discard d.handleEvent(deForceHide)
  d.anim = 0.0

proc isVisible*(d: DialogSM): bool =
  ## Check if dialog is visible - compatible with existing code
  d.state != dsHidden and d.anim > 0

proc isInteractive*(d: DialogSM): bool =
  ## Check if dialog is accepting input
  d.state == dsVisible

proc isProcessing*(d: DialogSM): bool =
  ## Check if dialog is processing
  d.state == dsProcessing

proc confirm*(d: var DialogSM): bool =
  ## User confirmed action
  if d.state == dsVisible:
    d.clickedPrimary = true
    return d.handleEvent(deConfirm)
  return false

proc cancel*(d: var DialogSM): bool =
  ## User cancelled
  if d.state == dsVisible:
    return d.handleEvent(deCancel)
  return false

proc processingComplete*(d: var DialogSM): bool =
  ## Processing complete, close dialog
  if d.state == dsProcessing:
    return d.handleEvent(deProcessComplete)
  return false

proc update*(d: var Dialog, speed: float32): tuple[shouldDraw: bool, anim: float32] =
  ## Update dialog animation and state
  ## Returns (shouldDraw, anim) for backward compatibility
  case d.state
  of dsHidden:
    d.anim = 0.0
    result = (false, 0.0)
  of dsOpening:
    d.anim = min(1.0, d.anim + speed)
    if d.anim >= 1.0:
      discard d.handleEvent(deOpenComplete)
    result = (true, d.anim)
  of dsVisible:
    d.anim = 1.0
    result = (true, 1.0)
  of dsProcessing:
    d.anim = 1.0
    result = (true, 1.0)
  of dsClosing:
    d.anim = max(0.0, d.anim - speed)
    if d.anim <= 0.0:
      discard d.handleEvent(deCloseComplete)
    result = (d.anim > 0, d.anim)

proc clickedPrimary*(d: Dialog): bool =
  ## Check if primary button was clicked - compatible with existing code
  d.clickedPrimary
