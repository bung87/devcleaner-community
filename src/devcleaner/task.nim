import std/[os, times]
import chronicles
import darwin/foundation
import ./[filesize, types, macos_utils]


method scan*(task: Task) {.base.} =
  if task.scanProc != nil:
    task.scanProc(task)
  else:
    error "No scanProc set for task", name = task.app

method recalculate*(task: Task) {.base.} =
  var total: int64 = 0
  for item in task.cache:
    total += item.size

  if task.onTaskData != nil:
    if total == 0:
      task.onTaskData(TaskData(name: task.app, info: "No cache found"))
    else:
      task.onTaskData(TaskData(name: task.app, info: fileSizeHumanReadable(total)))

  task.cache.setLen(0)

proc initChannel*(task: Task) =
  if task.channel == nil:
    task.channel = cast[ptr Channel[Message]](alloc0(sizeof(Channel[Message])))
    task.channel[].open()

proc closeChannel*(task: Task) =
  if task.channel != nil:
    task.channel[].close()
    dealloc(task.channel)
    task.channel = nil

proc pollMessages*(task: Task): bool =
  ## Polls for messages. Returns true if task is complete.
  result = false
  if task.channel == nil:
    return true

  while true:
    let recvResult = task.channel[].tryRecv()
    if not recvResult.dataAvailable:
      break

    let msg = recvResult.msg
    case msg.kind
    of mkScanDone:
      task.isScanning = false
      if task.onTaskState != nil:
        task.onTaskState(TaskState(
          name: task.app,
          status: tsDone,
          taskType: ttScan,
          total: msg.total,
          duration: msg.duration
        ))
      return true
    of mkCleanDone:
      task.isCleaning = false
      if task.onTaskState != nil:
        task.onTaskState(TaskState(
          name: task.app,
          status: tsDone,
          taskType: ttClean,
          total: msg.total,
          duration: msg.duration
        ))
      return true
    of mkCleanStart:
      # Internal signal, ignore in main thread
      discard
    of mkScanResult:
      if task.isScanning:
        task.addCacheEntry(DirInfo(name: msg.dir, size: msg.size, lastAccessed: msg.lastAccessed, projectDescription: msg.projectDescription))
      if task.onTaskData != nil:
        task.onTaskData(TaskData(name: task.app, info: msg.dir & " " & fileSizeHumanReadable(msg.size)))
      if task.onDirInfo != nil:
        task.onDirInfo(DirInfo(name: msg.dir, size: msg.size, lastAccessed: msg.lastAccessed, projectDescription: msg.projectDescription))
    of mkScan:
      discard


type
  ThreadProc* = proc(channel: ptr Channel[Message]) {.thread.}

proc startAsync*(task: Task, worker: ThreadProc, taskType: TaskType) =
  initChannel(task)
  if taskType == ttScan:
    task.isScanning = true
    task.cache.setLen(0)
  else:
    task.isCleaning = true
  createThread(task.thread, worker, task.channel)

proc cleanWorker(channel: ptr Channel[Message]) {.thread.} =
  ## Worker thread for async cleaning
  ## Uses a two-phase approach to avoid blocking
  var msg: Message
  var total: int64 = 0
  var appName: string = ""
  var dirsToClean: seq[tuple[path: string, size: int64]] = @[]
  
  # Phase 1: Collect all directories (with timeout)
  var lastMsgTime = getTime()
  while true:
    let recvResult = channel[].tryRecv()
    if not recvResult.dataAvailable:
      # Check if we've been waiting too long (5 seconds timeout)
      if (getTime() - lastMsgTime).inMilliseconds > 5000:
        break
      sleep(1)
      continue
    
    lastMsgTime = getTime()
    msg = recvResult.msg
    
    case msg.kind
    of mkScan:
      appName = msg.name
    of mkScanResult:
      dirsToClean.add((path: msg.dir, size: msg.size))
    of mkCleanStart:
      break
    of mkCleanDone, mkScanDone:
      discard
  
  # Phase 2: Clean all collected directories
  for dirInfo in dirsToClean:
    try:
      if dirExists(dirInfo.path):
        when defined(macosx):
          if moveToTrash(dirInfo.path):
            total += dirInfo.size
          else:
            warn "Failed to move to trash", path = dirInfo.path
        else:
          removeDir(dirInfo.path)
          total += dirInfo.size
      else:
        debug "Directory already removed", path = dirInfo.path
    except CatchableError as e:
      error "Failed to remove directory", path = dirInfo.path
  
  # Phase 3: Send completion message
  var doneMsg = Message(kind: mkCleanDone, name: appName, total: total)
  channel[].send(doneMsg)

proc startCleanAsync*(task: Task) =
  ## Start async clean operation
  debug "Starting async clean", appName = task.app, itemCount = task.cache.len
  initChannel(task)
  task.isCleaning = true
  createThread(task.thread, cleanWorker, task.channel)
  
  # Send start signal with app name
  var startMsg = Message(kind: mkScan, name: task.app)
  task.channel[].send(startMsg)
  
  # Send all directories to clean
  for item in task.cache:
    var msg = Message(kind: mkScanResult, name: task.app, dir: item.name, size: item.size)
    task.channel[].send(msg)
  
  # Send signal that all directories have been sent
  var doneSignal = Message(kind: mkCleanStart, name: task.app)
  task.channel[].send(doneSignal)
