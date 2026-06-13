import std/os
import ./getattrlistbulk_bindings

## High-level Nim API for macOS getattrlistbulk() system call
## This provides high-performance bulk metadata retrieval for directories
##
## Usage:
##   for entry in walkDirBulk("/path/to/dir"):
##     echo entry.name, " ", entry.size
##
##   let totalSize = directorySizeBulk("/path/to/dir")

export getattrlistbulk_bindings.DirectoryEntry

proc initAttrList(): attrlist =
  result.bitmapcount = ATTR_BIT_MAP_COUNT
  result.reserved = 0
  # ATTR_CMN_NAME and ATTR_CMN_RETURNED_ATTRS are REQUIRED by getattrlistbulk
  result.commonattr = ATTR_CMN_NAME or ATTR_CMN_OBJTYPE or ATTR_CMN_RETURNED_ATTRS
  result.volattr = 0
  result.dirattr = 0
  result.fileattr = ATTR_FILE_TOTALSIZE
  result.forkattr = 0

# Parse a single entry from the buffer
# Buffer format when ATTR_CMN_RETURNED_ATTRS is requested:
# - uint32_t: entry length (4 bytes)
# - attribute_set: returned_attrs (20 bytes)
# - attrreference: name reference (8 bytes)
# - uint32_t: objtype (4 bytes)
# - uint64_t: file size (8 bytes, only if returned_attrs.fileattr has ATTR_FILE_TOTALSIZE bit set)
# - name: null-terminated string (variable length, location specified by name reference)
proc parseEntry(buf: pointer, bufSize: int): tuple[name: string, size: int64, objType: uint32, entryLen: int] =
  var offset = 0

  # Read entry length (first 4 bytes)
  let entryLen = cast[ptr uint32](cast[int](buf) + offset)[].int
  if entryLen == 0 or entryLen > bufSize:
    return ("", 0'i64, 0'u32, 0)
  offset += 4

  # Read the returned_attrs attribute_set (20 bytes) to check what attrs were returned
  let returnedAttrs = cast[ptr attribute_set](cast[int](buf) + offset)[]
  offset += sizeof(attribute_set).int

  # Read name attribute reference (8 bytes)
  let nameRefPos = offset  # Remember where the name reference is
  let nameRef = cast[ptr attrreference](cast[int](buf) + offset)[]
  offset += sizeof(attrreference).int

  # Read object type (4 bytes)
  let objType = cast[ptr uint32](cast[int](buf) + offset)[]
  offset += 4

  # Read file size only if it was returned (check returned_attrs.fileattr)
  var fileSize: uint64 = 0
  if (returnedAttrs.fileattr and ATTR_FILE_TOTALSIZE) != 0:
    fileSize = cast[ptr uint64](cast[int](buf) + offset)[]
  offset += 8

  # Get the name from the reference
  # The name is at: nameRefPos + nameRef.attr_dataoffset
  var name = ""
  if nameRef.attr_length > 0:
    let nameOffset = nameRefPos + nameRef.attr_dataoffset.int
    if nameOffset >= 0 and nameOffset + nameRef.attr_length.int <= entryLen:
      let namePtr = cast[pointer](cast[int](buf) + nameOffset)
      let nameLen = nameRef.attr_length.int - 1  # Exclude null terminator
      if nameLen > 0:
        name = newString(nameLen)
        copyMem(addr name[0], namePtr, nameLen)

  return (name, fileSize.int64, objType, entryLen)

iterator walkDirBulk*(path: string, bufferSize: int = 64 * 1024): DirectoryEntry =
  ## High-performance directory walker using getattrlistbulk
  ## Yields DirectoryEntry for each file/directory found

  let fd = open(path.cstring, O_RDONLY or O_DIRECTORY)
  if fd < 0:
    raiseOSError(osLastError(), "Failed to open directory: " & path)

  defer:
    discard close(fd)

  var alist = initAttrList()
  var buffer = newSeq[byte](bufferSize)

  while true:
    let count = getattrlistbulk(
      fd,
      addr alist,
      addr buffer[0],
      bufferSize.csize_t,
      0'u64
    )

    if count < 0:
      let err = osLastError()
      raiseOSError(err, "getattrlistbulk failed for: " & path)

    if count == 0:
      break

    var offset = 0
    for i in 0 ..< count:
      let (name, size, objType, entryLen) = parseEntry(addr buffer[offset], bufferSize - offset)

      if entryLen == 0:
        break

      var entry: DirectoryEntry
      entry.name = name
      entry.size = size
      entry.isDir = objType == VDIR
      entry.isFile = objType == VREG

      yield entry

      offset += entryLen
      # Align to 4-byte boundary (required by the API)
      offset = (offset + 3) and not 3

proc directorySizeBulk*(path: string, bufferSize: int = 64 * 1024): int64 =
  ## Calculate total size of directory using getattrlistbulk
  ## Much faster than traditional walkDirRec for large directories

  if not dirExists(path):
    return 0

  var stack: seq[string] = @[path]

  while stack.len > 0:
    let currentDir = stack.pop()

    for entry in walkDirBulk(currentDir, bufferSize):
      if entry.isFile:
        result += entry.size
      elif entry.isDir and entry.name != "." and entry.name != "..":
        let subPath = currentDir / entry.name
        stack.add(subPath)
