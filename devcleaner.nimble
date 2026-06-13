# Package

version       = "1.0.1"
author        = "DevCleaner Contributors"
description   = "DevCleaner - Clean development cache files"
license       = "MIT"
bin           = @["devcleaner"]
srcDir        = "src"
# Dependencies

requires "nim >= 2.0.0"
requires "https://github.com/RowDaBoat/nglfw"
requires "nanovg"
requires "pixie >= 6.0.0"
requires "chroma"
requires "nregex >= 0.0.4"
requires "https://github.com/heuer/scfg-nim"
requires "https://github.com/juancarlospaco/psutil-nim >= 0.6.1"
requires "darwin"
requires "chronicles"
requires "yanyl >= 1.3.0"
