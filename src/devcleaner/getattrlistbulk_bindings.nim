## Low-level bindings for macOS getattrlistbulk() system call
## This module provides the C interface and type definitions
## Reference: https://github.com/quivent/getattrlistbulk-rs

when not defined(macosx):
  {.error: "getattrlistbulk is only available on macOS".}

type
  attrlist* {.importc: "struct attrlist", header: "<sys/attr.h>", bycopy.} = object
    bitmapcount*: uint16
    reserved*: uint16
    commonattr*: uint32
    volattr*: uint32
    dirattr*: uint32
    fileattr*: uint32
    forkattr*: uint32

  attrreference* {.importc: "struct attrreference", header: "<sys/attr.h>", bycopy.} = object
    attr_dataoffset*: int32
    attr_length*: uint32

  ## This structure represents the returned_attrs field when ATTR_CMN_RETURNED_ATTRS is requested
  attribute_set* {.importc: "struct attribute_set", header: "<sys/attr.h>", bycopy.} = object
    commonattr*: uint32
    volattr*: uint32
    dirattr*: uint32
    fileattr*: uint32
    forkattr*: uint32

type
  DirectoryEntry* = object
    name*: string
    size*: int64
    isFile*: bool
    isDir*: bool

const
  ATTR_BIT_MAP_COUNT* = 5'u16

  # Common attributes
  ATTR_CMN_NAME* = 0x00000001'u32
  ATTR_CMN_OBJTYPE* = 0x00000008'u32
  ATTR_CMN_RETURNED_ATTRS* = 0x80000000'u32  # REQUIRED by getattrlistbulk

  # File attributes
  ATTR_FILE_TOTALSIZE* = 0x00000002'u32

  # Object types
  VREG* = 1  # Regular file
  VDIR* = 2  # Directory

  # Open flags (macOS specific)
  O_RDONLY* = 0
  O_DIRECTORY* = 0x00100000

proc getattrlistbulk*(
  fd: cint,
  attrList: ptr attrlist,
  attrBuf: pointer,
  attrBufSize: csize_t,
  options: uint64
): cint {.importc: "getattrlistbulk", header: "<sys/attr.h>".}

proc open*(path: cstring, flags: cint, mode: cint = 0o666): cint {.importc: "open", header: "<fcntl.h>".}
proc close*(fd: cint): cint {.importc: "close", header: "<unistd.h>".}
