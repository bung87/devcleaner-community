import std/[os, times, strformat]
import src/[getattrlistbulk, utils]

proc testDirectorySize() =
  echo "Testing directory size calculation..."
  
  # Test with current directory
  let testDir = "."
  
  echo "\n--- Testing getattrlistbulk implementation ---"
  let start1 = cpuTime()
  let size1 = directorySizeBulk(testDir)
  let elapsed1 = cpuTime() - start1
  echo &"getattrlistbulk: {size1} bytes in {elapsed1:.4f}s"
  
  echo "\n--- Testing original walkDirRec implementation ---"
  let start2 = cpuTime()
  var size2: int64 = 0
  for path in walkDirRec(testDir):
    if fileExists(path):
      try:
        size2 += getFileSize(path)
      except:
        discard
  let elapsed2 = cpuTime() - start2
  echo &"walkDirRec: {size2} bytes in {elapsed2:.4f}s"
  
  echo &"\n--- Results ---"
  echo &"Size difference: {size1 - size2} bytes"
  echo &"Speedup: {elapsed2/elapsed1:.2f}x"

proc testWalkDirBulk() =
  echo "\n--- Testing walkDirBulk iterator ---"
  var count = 0
  for entry in walkDirBulk("."):
    if count < 10:
      let typeStr = if entry.isDir: "DIR" elif entry.isFile: "FILE" else: "OTHER"
      echo &"  {typeStr:5} {entry.size:10} {entry.name}"
    count += 1
  echo &"  ... and {count - 10} more entries"

when isMainModule:
  when defined(macosx):
    testWalkDirBulk()
    testDirectorySize()
  else:
    echo "This test only runs on macOS"
