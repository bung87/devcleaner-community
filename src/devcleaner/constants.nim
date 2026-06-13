# Directories to skip (avoid touching)
import std/[os]
import std/[parsecfg, streams]

const ProjectDir = currentSourcePath.parentDir.parentDir.parentDir
const NimbleFile = ProjectDir / "devcleaner.nimble"
const NimbleContent = staticRead(NimbleFile)
const Version* = NimbleContent.newStringStream.loadConfig.getSectionValue("", "version")
const MetaFile = ProjectDir / "nimpacker" / "meta.nims"
const MetaContent = staticRead(MetaFile)
const Copyright* = MetaContent.newStringStream.loadConfig.getSectionValue("", "copyright")
const AppName* = MetaContent.newStringStream.loadConfig.getSectionValue("", "productName")

# Builtin config content - embedded at compile time
const BuiltinConfigFile* = ProjectDir / "config" / "builtin.scfg"
const BuiltinConfigContent* = staticRead(BuiltinConfigFile)

const SkipDirs* = [
  "~/Downloads",
  # System directories - avoid touching entirely
  "/Library",  # System-wide cache, logs, and app data
  "/var/log",  # Unix-level system logs (kernel, system services)
  "/private/var/folders",  # macOS temp/sandbox cache (auto-managed)
  # User directories
  "~/Library",  # User app data, preferences, caches
  "~/Applications",
  "/Applications",
  "~/Pictures"
]
