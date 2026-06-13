import psutil
import ./filesize
import chronicles

type
  DiskInfo* = object
    total*: int64
    free*: int64

proc getDiskSpaceInfo*(): DiskInfo =
  ## Get disk space information using psutil
  try:
    let usage = disk_usage("/")
    return DiskInfo(
      total: usage.total,
      free: usage.free
    )
  except CatchableError as e:
    debug "Failed to get disk usage", error = e.msg
    return DiskInfo(total: 0, free: 0)

proc formatDiskInfo*(info: DiskInfo): tuple[total, free: string] =
  result = (
    total: fileSizeHumanReadable(info.total),
    free: fileSizeHumanReadable(info.free)
  )
