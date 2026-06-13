## Apple Intelligence Integration via Shortcuts
##
## This module provides access to macOS Apple Intelligence features
## through the Shortcuts app. Users need to create a Shortcut named
## "Summarize Text" that uses the Apple Intelligence "Summarize" action.
##
## To set up:
## 1. Open Shortcuts app on macOS
## 2. Create new shortcut named "Summarize Text"
## 3. Add "Receive Text" action (set to "Plain Text")
## 4. Add "Summarize" action (Apple Intelligence)
## 5. Add "Return" action
## 6. Save the shortcut

import std/[os, osproc, strutils]
import chronicles

const
  DefaultShortcutName = "Summarize Text"
  DefaultTimeoutMs = 10000

proc isAppleIntelligenceAvailable*(): bool =
  ## Check if Apple Intelligence is available on this system
  ## Requires macOS Sequoia 15.1+ and Apple Silicon (or compatible Intel Mac)
  
  # Check macOS version (Sequoia 15.1+)
  let (versionOutput, versionExit) = execCmdEx("sw_vers -productVersion")
  if versionExit != 0:
    return false
  
  let version = versionOutput.strip()
  let versionParts = version.split(".")
  if versionParts.len >= 2:
    try:
      let major = parseInt(versionParts[0])
      let minor = parseInt(versionParts[1])
      # Need macOS 15.1 or later
      if major < 15 or (major == 15 and minor < 1):
        return false
    except:
      return false
  
  # Check if Shortcuts app is available
  if not fileExists("/System/Applications/Shortcuts.app/Contents/MacOS/Shortcuts"):
    return false
  
  # Check if the "Summarize Text" shortcut exists
  let (listOutput, listExit) = execCmdEx("shortcuts list")
  if listExit != 0:
    return false
  
  return DefaultShortcutName in listOutput

proc summarizeWithAppleIntelligence*(
  text: string,
  shortcutName: string = DefaultShortcutName,
  timeoutMs: int = DefaultTimeoutMs
): string =
  ## Summarize text using Apple Intelligence via Shortcuts
  ## Returns empty string if summarization fails
  
  result = ""
  
  if text.len == 0:
    return
  
  # Escape the input text for shell
  # Replace backslashes first, then quotes
  var escapedText = text.replace("\\", "\\\\")
  escapedText = escapedText.replace("\"", "\\\"")
  escapedText = escapedText.replace("$", "\\$")
  escapedText = escapedText.replace("`", "\\`")
  
  # Create a temporary file for the input to avoid command line length issues
  let tempFile = getTempDir() / "devcleaner_ai_input.txt"
  try:
    writeFile(tempFile, text)
  except:
    debug "Failed to write temp file for Apple Intelligence"
    return
  
  defer:
    try:
      removeFile(tempFile)
    except:
      discard
  
  # Call the shortcut with the file input
  let cmd = "shortcuts run \"" & shortcutName & "\" -i \"" & tempFile & "\""
  
  debug "Calling Apple Intelligence via Shortcuts", cmd = cmd
  
  let (output, exitCode) = execCmdEx(cmd)
  
  if exitCode == 0:
    result = output.strip()
    debug "Apple Intelligence summarization succeeded", length = result.len
  else:
    debug "Apple Intelligence shortcut failed", exitCode = exitCode

proc getProjectSummaryWithAI*(readmeContent: string): string =
  ## Get a project summary using Apple Intelligence
  ## Falls back to empty string if AI is not available or fails
  
  if not isAppleIntelligenceAvailable():
    debug "Apple Intelligence not available"
    return ""
  
  # Prepare the content for summarization
  # Limit the content length to avoid overwhelming the AI
  let maxLength = 2000
  var content = readmeContent
  if content.len > maxLength:
    content = content[0..<maxLength] & "..."
  
  # Add a prompt prefix to guide the summarization
  let prompt = "Please summarize what this project does in one concise sentence:\n\n" & content
  
  result = summarizeWithAppleIntelligence(prompt)
  
  # Clean up the result
  if result.len > 0:
    # Remove quotes if the AI added them
    if result.startswith("\"") and result.endswith("\""):
      result = result[1..^2]
    result = result.strip()
