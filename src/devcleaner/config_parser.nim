import std/[os, options, streams]
import scfg
import ./types


## Custom Directive type to represent parsed scfg structure
type
  Directive* = ref object
    name*: string
    params*: seq[string]
    children*: seq[Directive]

proc parseSearchType(s: string): SearchType =
  case s
  of "static": stStatic
  of "recursive": stRecursive
  of "regex": stRegex
  else: stStatic

proc parseSearchConfigStatic(directive: Directive): SearchConfig =
  var base = ""
  var skipDirs: seq[string] = @[]
  var staticDirs: seq[string] = @[]

  for child in directive.children:
    case child.name
    of "base":
      if child.params.len > 0:
        base = child.params[0]
    of "dirs":
      staticDirs = child.params
    of "skip_dirs":
      for param in child.params:
        skipDirs.add(expandTilde(param))
    else: discard

  result = SearchConfig(
    kind: stStatic,
    searchType: stStatic,
    base: base,
    skipDirs: skipDirs,
    staticDirs: staticDirs
  )

proc parseSearchConfigRecursive(directive: Directive): SearchConfig =
  var base = ""
  var skipDirs: seq[string] = @[]
  var recursiveTargets: seq[string] = @[]
  var recursiveMarkers: seq[string] = @[]
  var recursiveSkipHidden = false
  var recursiveAllowHidden: seq[string] = @[]

  for child in directive.children:
    case child.name
    of "base":
      if child.params.len > 0:
        base = child.params[0]
    of "target":
      # Single target
      if child.params.len > 0:
        recursiveTargets.add(child.params[0])
    of "targets":
      # Multiple targets
      for param in child.params:
        recursiveTargets.add(param)
    of "markers":
      recursiveMarkers = child.params
    of "skip_hidden":
      if child.params.len > 0:
        recursiveSkipHidden = child.params[0] == "true"
    of "allow_hidden":
      recursiveAllowHidden = child.params
    of "skip_dirs":
      for param in child.params:
        skipDirs.add(expandTilde(param))
    else: discard

  result = SearchConfig(
    kind: stRecursive,
    searchType: stRecursive,
    base: base,
    skipDirs: skipDirs,
    recursiveTargets: recursiveTargets,
    recursiveMarkers: recursiveMarkers,
    recursiveSkipHidden: recursiveSkipHidden,
    recursiveAllowHidden: recursiveAllowHidden
  )

proc parseSearchConfigRegex(directive: Directive): SearchConfig =
  var base = ""
  var skipDirs: seq[string] = @[]
  var regexPattern = ""
  var regexSkipHiddenExcept: seq[string] = @[]

  for child in directive.children:
    case child.name
    of "base":
      if child.params.len > 0:
        base = child.params[0]
    of "pattern":
      if child.params.len > 0:
        regexPattern = child.params[0]
    of "skip_hidden_except":
      regexSkipHiddenExcept = child.params
    of "skip_dirs":
      for param in child.params:
        skipDirs.add(expandTilde(param))
    else: discard

  result = SearchConfig(
    kind: stRegex,
    searchType: stRegex,
    base: base,
    skipDirs: skipDirs,
    regexPattern: regexPattern,
    regexSkipHiddenExcept: regexSkipHiddenExcept
  )

proc parseSearchConfig(directive: Directive): SearchConfig =
  var searchType = stStatic

  for child in directive.children:
    if child.name == "type" and child.params.len > 0:
      searchType = parseSearchType(child.params[0])
      break

  case searchType
  of stStatic:
    result = parseSearchConfigStatic(directive)
  of stRecursive:
    result = parseSearchConfigRecursive(directive)
  of stRegex:
    result = parseSearchConfigRegex(directive)

proc parseTaskConfig(directive: Directive, configType: ConfigType = ctProject): TaskConfig =
  result = newTaskConfig(
    if directive.params.len > 0: directive.params[0] else: "unknown",
    configType
  )

  for child in directive.children:
    case child.name
    of "tool":
      if child.params.len > 0:
        result.tool = child.params[0]
    of "bin":
      # Single binary
      if child.params.len > 0:
        result.bin.add(child.params[0])
    of "bins":
      # Multiple binaries - any match will show the app
      result.bin = child.params
    of "search":
      result.search = some(parseSearchConfig(child))
    else: discard

## Parse scfg content using the new event-based API
proc readScfg*(content: string): seq[Directive] =
  ## Parse scfg string and return a sequence of Directive objects
  ## 
  var stack: seq[Directive] = @[]
  let stream = newStringStream(content)
  defer: stream.close()

  for event in parse_scfg(stream):
    case event.kind
    of evt_start:
      let directive = Directive(
        name: event.name,
        params: event.params,
        children: @[]
      )
      if stack.len == 0:
        result.add(directive)
      else:
        stack[^1].children.add(directive)
      if event.has_block:
        stack.add(directive)
    of evt_end:
      if event.has_block:
        discard stack.pop()

proc parseConfig*(content: string): seq[TaskConfig] =
  ## Parse config content into seq[TaskConfig]

  let directives = readScfg(content)
  for directive in directives:
    case directive.name
    of "project":
      result.add(parseTaskConfig(directive, ctProject))
    of "system":
      result.add(parseTaskConfig(directive, ctSystem))
