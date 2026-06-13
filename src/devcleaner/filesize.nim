import std/[math, strutils]

const
  units = ["bytes", "KB", "MB", "GB", "TB", "PB", "EB", "ZB", "YB"]
  marketingDivider = 1000

proc fileSizeHumanReadable*(size: int64): string =
  ## Convert file size to human-readable string
  ## Uses base-1000 (marketing) units: KB, MB, GB, etc.
  ## Returns "0 bytes" for zero or negative sizes
  
  if size <= 0:
    return "0 bytes"
  
  # Handle bytes case directly (no division needed)
  if size < marketingDivider:
    return $size & " bytes"
  
  var key = 1  # Start at KB (index 1)
  while key < units.len:
    let currentThreshold = marketingDivider.float.pow(key.float).int64
    let nextThreshold = marketingDivider.float.pow((key + 1).float).int64

    if size < nextThreshold:
      # Found the right unit
      let r = size.float / currentThreshold.float
      let rInt = r.int
      if r == rInt.float:
        return $rInt & " " & units[key]
      else:
        return r.formatFloat(ffDecimal, precision=2) & " " & units[key]
    key += 1

  # Fallback for extremely large sizes (YB+)
  let r = size.float / marketingDivider.float.pow((units.len - 1).float)
  return r.formatFloat(ffDecimal, precision=2) & " " & units[^1]
