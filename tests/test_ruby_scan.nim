import std/[os, times, strformat, strutils]
import nregex
import ../src/[types, config_loader, constants]

## Test Ruby scanning performance
## The Ruby config uses regex pattern: \.rvm/gems/ruby-(\d+\.\d+(?:\.\d+)?)/cache
## to search in the home directory

proc testRubyScanPerformance() =
  echo "=== Ruby Scan Performance Test ==="
  echo ""

  # Create a SearchConfig for regex type (variant object needs proper initialization)
  # For variant objects, we need to initialize with the correct case branch
  var config = SearchConfig(
    searchType: stRegex,
    kind: stRegex,  # This sets the discriminator
    base: "~",
    skipDirs: @[
      expandTilde("~/Applications"),
      expandTilde("~/Desktop"),
      expandTilde("~/Movies"),
      expandTilde("~/Music"),
      expandTilde("~/Pictures"),
      expandTilde("~/Public")
    ],
    regexPattern: "\\.rvm/gems/ruby-(\\d+\\.\\d+(?:\\.\\d+)?)/cache",
    regexSkipHiddenExcept: @[".rvm"]
  )

  let baseDir = expandTilde(config.base)
  echo "Base directory: ", baseDir
  echo "Regex pattern: ", config.regexPattern
  echo "Skip directories: ", config.skipDirs
  echo ""

  # Test 1: Count total directories that will be scanned
  echo "--- Test 1: Counting directories to scan ---"
  var dirCount = 0
  var hiddenDirCount = 0
  var skippedDirCount = 0

  let pattern = re(config.regexPattern)
  var matchCount = 0

  proc countDirs(dir: string, level: int = 0) =
    if level > 10:  # Limit depth for safety
      return

    let baseName = extractFilename(dir)

    # Check if hidden
    if baseName.startswith("."):
      hiddenDirCount += 1
      if baseName notin config.regexSkipHiddenExcept:
        skippedDirCount += 1
        return

    # Check if in skip list
    if dir in config.skipDirs:
      skippedDirCount += 1
      return

    dirCount += 1

    # Check if matches pattern
    var m: RegexMatch
    if nregex.find(dir, pattern, m):
      matchCount += 1
      echo "  Match: ", dir

    # Recurse
    try:
      for kind, path in walkDir(dir):
        if kind == pcDir:
          countDirs(path, level + 1)
    except:
      discard

  let startCount = cpuTime()
  countDirs(baseDir)
  let countTime = cpuTime() - startCount

  echo ""
  echo "Results:"
  echo "  Total directories scanned: ", dirCount
  echo "  Hidden directories: ", hiddenDirCount
  echo "  Skipped directories: ", skippedDirCount
  echo "  Regex matches: ", matchCount
  echo "  Counting time: ", countTime.formatFloat(ffDecimal, 4), "s"
  echo ""

  # Test 2: Test regex performance on paths
  echo "--- Test 2: Regex performance test ---"

  # Generate test paths that might be scanned
  var testPaths: seq[string] = @[]

  proc collectPaths(dir: string, level: int = 0) =
    if level > 5 or testPaths.len > 10000:
      return

    let baseName = extractFilename(dir)

    if baseName.startswith(".") and baseName notin config.regexSkipHiddenExcept:
      return

    if dir in config.skipDirs:
      return

    testPaths.add(dir)

    try:
      for kind, path in walkDir(dir):
        if kind == pcDir:
          collectPaths(path, level + 1)
    except:
      discard

  collectPaths(baseDir)
  echo "Collected ", testPaths.len, " paths for regex testing"

  # Test regex matching performance
  let startRegex = cpuTime()
  var regexMatches = 0
  for path in testPaths:
    var m: RegexMatch
    if nregex.find(path, pattern, m):
      regexMatches += 1
  let regexTime = cpuTime() - startRegex

  echo "Regex matching:"
  echo "  Paths tested: ", testPaths.len
  echo "  Matches found: ", regexMatches
  echo "  Total time: ", regexTime.formatFloat(ffDecimal, 4), "s"
  if testPaths.len > 0:
    echo "  Time per path: ", (regexTime / float(testPaths.len) * 1000000).formatFloat(ffDecimal, 4), "µs"
  echo ""

  # Test 3: Profile specific slow areas
  echo "--- Test 3: Profiling walkDir performance ---"

  proc profileWalkDir(dir: string, level: int = 0): tuple[dirs: int, time: float] =
    if level > 3:  # Only go 3 levels deep for profiling
      return (0, 0.0)

    var totalDirs = 0
    var totalTime = 0.0

    let start = cpuTime()
    var subdirs: seq[string] = @[]

    try:
      for kind, path in walkDir(dir):
        if kind == pcDir:
          subdirs.add(path)
    except:
      discard

    let walkTime = cpuTime() - start
    totalTime += walkTime
    totalDirs += subdirs.len

    # Recurse
    for subdir in subdirs:
      let (d, t) = profileWalkDir(subdir, level + 1)
      totalDirs += d
      totalTime += t

    return (totalDirs, totalTime)

  let (profiledDirs, profiledTime) = profileWalkDir(baseDir)
  echo "  Profiled ", profiledDirs, " directories in ", profiledTime.formatFloat(ffDecimal, 4), "s"
  if profiledDirs > 0:
    echo "  Average time per directory: ", (profiledTime / float(profiledDirs) * 1000).formatFloat(ffDecimal, 4), "ms"
  echo ""

  # Test 4: Check if .rvm directory exists
  echo "--- Test 4: RVM directory check ---"
  let rvmDir = expandTilde("~/.rvm")
  if dirExists(rvmDir):
    echo "  .rvm directory exists: ", rvmDir

    # Count gems directories
    var gemsDirs = 0
    var cacheDirs = 0

    proc countRvmDirs(dir: string, level: int = 0) =
      if level > 5:
        return

      let baseName = extractFilename(dir)

      if baseName == "gems":
        gemsDirs += 1
      if baseName == "cache":
        cacheDirs += 1
        echo "    Found cache dir: ", dir

      try:
        for kind, path in walkDir(dir):
          if kind == pcDir:
            countRvmDirs(path, level + 1)
      except:
        discard

    countRvmDirs(rvmDir)
    echo "  Gems directories found: ", gemsDirs
    echo "  Cache directories found: ", cacheDirs
  else:
    echo "  .rvm directory NOT found at: ", rvmDir
    echo "  Ruby/RVM may not be installed"
  echo ""

  # Analysis
  echo "=== Analysis ==="
  if countTime > 1.0:
    echo "⚠️  Scan took longer than 1 second!"
    echo "   Possible issues:"
    echo "   - Too many directories being scanned"
    echo "   - Regex pattern is slow (backtracking)"
    echo "   - walkDir is slow on certain directories"
  else:
    echo "✓ Scan completed in reasonable time"

  if dirCount > 10000:
    echo "⚠️  Large number of directories (", dirCount, ") - consider adding more skip patterns"

  if matchCount == 0:
    echo "⚠️  No matches found - pattern may be incorrect or RVM not installed"

  if regexTime > 0.5:
    echo "⚠️  Regex matching is slow (", regexTime.formatFloat(ffDecimal, 4), "s)"
    echo "   Consider optimizing the regex pattern"

when isMainModule:
  testRubyScanPerformance()
