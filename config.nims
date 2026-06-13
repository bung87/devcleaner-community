when defined(macosx):

  # switch("passC", "-Wno-incompatible-function-pointer-types")
  when defined(arm64):
    # https://developer.apple.com/documentation/xcode/diagnosing-memory-thread-and-crash-issues-early
    # switch("passC", "-fsanitize=null")
    switch("passC", "-arch arm64")
    switch("passL", "-arch arm64")
    # switch("passC", "-target arm64-apple-macos11")
    # switch("passL", "-target arm64-apple-macos11")

  when defined(amd64):
    switch("passC", "-arch x86_64")
    switch("passL", "-arch x86_64")
    # switch("passC", "-target x86_64-apple-macos10.12")
    # switch("passL", "-target x86_64-apple-macos10.12")


# Set log level to INFO to capture scan results (debug is too verbose)
switch("define", "chronicles_log_level=INFO")

# Use textlines format for human-readable output
# Note: The actual log file path is set at runtime in initApp() to:
#   ~/Library/Logs/bale sheet/crown_excel.log
switch("define", "chronicles_sinks=textlines[file]")

# Disable thread ID in log output
switch("define", "chronicles_thread_ids=no")
switch("define", "glfwStaticLib")
# begin Nimble config (version 2)
when withDir(thisDir(), system.fileExists("nimble.paths")):
  include "nimble.paths"
# end Nimble config
