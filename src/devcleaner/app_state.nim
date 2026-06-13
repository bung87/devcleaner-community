## Minimal State Management

import ./native_toolbar
import ./macos_utils

type AppState* = enum asScan, asScanning, asClean

var currentAppState*: AppState = asScan

proc getAppState*(): AppState = currentAppState

proc setAppState*(s: AppState) =
  currentAppState = s
  when defined(macosx):
    case s
    of asScan: updateToolbarButton(tbsScan)
    of asScanning: updateToolbarButton(tbsScanning)
    of asClean: 
      updateToolbarButton(tbsClean)
      playCompletionSound()
