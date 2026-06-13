#!/usr/bin/env nim

mode = ScriptMode.Verbose # or .Silent

import std/[os, strformat]
# import ../src/patchdriver
const APP_DIR {.strdefine.} = ""
const APP_FORMAT {.strdefine.} = ""

echo "Build directory: " & APP_DIR


when defined(macosx):
  const ResourcesDir = APP_DIR / "Contents" / "Resources"
  cpDir "assets", ResourcesDir / "assets"

