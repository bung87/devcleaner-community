import std/options

type
  SearchType* = enum
    stStatic
    stRecursive
    stRegex

  SearchConfig* = ref object
    searchType*: SearchType
    base*: string
    skipDirs*: seq[string]
    case kind*: SearchType
    of stStatic:
      staticDirs*: seq[string]
    of stRecursive:
      recursiveTargets*: seq[string]
      recursiveMarkers*: seq[string]
      recursiveSkipHidden*: bool
      recursiveAllowHidden*: seq[string]
    of stRegex:
      regexPattern*: string
      regexSkipHiddenExcept*: seq[string]

  ConfigType* = enum
    ctProject
    ctSystem

  TaskConfig* = ref object
    configType*: ConfigType
    name*: string
    tool*: string
    bin*: seq[string]  # Binaries to check (any match will show the app)
    search*: Option[SearchConfig]

proc newTaskConfig*(name: string, configType: ConfigType = ctProject): TaskConfig =
  result = TaskConfig(
    configType: configType,
    name: name,
  )



type
  TaskType* = enum
    ttScan
    ttClean

  TaskStatus* = enum
    tsProcess
    tsDone
    tsProcessing

  TaskData* = object
    name*: string
    info*: string

  TaskState* = object
    name*: string
    status*: TaskStatus
    taskType*: TaskType
    total*: int64
    duration*: float32  # Scanning/cleaning duration in seconds

  DirInfo* = ref object
    name*: string
    size*: int64
    lastAccessed*: string  # Formatted last accessed time
    projectDescription*: Option[string]  # AI-generated or extracted project description (None if not available)

  TaskCallback* = proc(data: TaskData)
  StateCallback* = proc(state: TaskState)

  # Message kinds for channel communication
  MessageKind* = enum
    mkScan
    mkScanResult
    mkScanDone
    mkCleanStart
    mkCleanDone

  # Unified message type for async communication
  # All fields are always present, use 'kind' to determine which are valid
  Message* = object
    name*: string
    case kind*: MessageKind
    of mkScanResult:
      dir*: string
      size*: int64
      lastAccessed*: string
      projectDescription*: Option[string]  # AI-generated or extracted project description (None if not available)

    of mkScanDone, mkCleanDone:
      total*: int64
      duration*: float32
    of mkScan, mkCleanStart:
      discard

# Thread argument type for passing channel and config info
type
  ScanWorkerArg* = tuple[chan: ptr Channel[Message], configName: string, configType: ConfigType]



const
  MaxCacheEntriesPerTask* = 10000  ## Maximum number of cache entries per task to prevent unbounded memory growth

type
  ScanProc* = proc(task: Task) {.nimcall.}
  CleanProc* = proc(task: Task) {.nimcall.}
  Task* = ref object of RootObj
    app*: string
    cache*: seq[DirInfo]
    onTaskData*: TaskCallback
    onTaskState*: StateCallback
    onDirInfo*: proc(info: DirInfo)
    isScanning*: bool
    isCleaning*: bool
    channel*: ptr Channel[Message]
    thread*: Thread[ptr Channel[Message]]
    taskConfig*: TaskConfig
    configThread*: Thread[ScanWorkerArg]
    scanProc*: ScanProc
    cleanProc*: CleanProc

proc addCacheEntry*(task: Task, entry: DirInfo) =
  ## Add a cache entry with size limit enforcement
  if task.cache.len >= MaxCacheEntriesPerTask:
    # Remove oldest 25% when limit reached
    let removeCount = MaxCacheEntriesPerTask div 4
    task.cache = task.cache[removeCount .. ^1]
  task.cache.add(entry)

proc newTask*(app: string): Task =
  result = Task(
    app: app,
  )

proc newTask*(config: TaskConfig): Task =
  result = Task(
    app: config.name,
    taskConfig: config,
  )

