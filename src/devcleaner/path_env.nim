import std/[os, strutils, osproc]
import chronicles

proc getUserPathFromShell*(): string =
  ## Get PATH from user's login shell
  ## This is needed because macOS .apps don't inherit shell environment
  let shell = getEnv("SHELL")
  if shell.len == 0:
    return ""

  # Build command to get PATH from login shell
  # Use -l flag for login shell to load profile
  let cmd = shell & " -l -c 'echo $PATH'"

  try:
    let (output, exitCode) = execCmdEx(cmd, options = {poUsePath})
    if exitCode == 0:
      let path = output.strip()
      if path.len > 0 and path.contains("/usr/bin"):
        return path
  except CatchableError:
    discard

  return ""

proc setupPath*() =
  ## Ensure PATH is set correctly when running from .app bundle
  ## macOS .apps don't inherit the user's shell PATH
  when defined(macosx):
    let currentPath = getEnv("PATH")

    # Check if PATH looks complete (has common system paths)
    let hasSystemPaths = currentPath.contains("/usr/bin") and
                         currentPath.contains("/bin")
    let hasUserPaths = currentPath.contains("/usr/local/bin") or
                       currentPath.contains("/opt/homebrew/bin")

    if hasSystemPaths and hasUserPaths:
      # PATH looks good, no need to modify
      return

    # Try to get PATH from user's login shell first
    let shellPath = getUserPathFromShell()

    if shellPath.len > 0:
      # Use the shell's PATH
      putEnv("PATH", shellPath)
      debug "PATH set from user shell"
    else:
      debug "Could not determine PATH from shell, leaving as is"
