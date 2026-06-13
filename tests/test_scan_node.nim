import std/[unittest, os, options, strutils]
import ../src/[config_loader, types, scanner, utils, constants]

suite "Node Config Scan Tests":
  test "Load node config from builtin":
    let configs = loadConfigFile(ConfigPath)

    var nodeConfig: TaskConfig
    var found = false
    for c in configs:
      if c.name == "node" and c.configType == ctProject:
        nodeConfig = c
        found = true
        break

    check found == true
    check nodeConfig.name == "node"
    check nodeConfig.configType == ctProject
    check nodeConfig.search.isSome == true
    echo "Node markers: ", nodeConfig.markers
    check nodeConfig.targets.len > 0
    echo "Node targets: ", nodeConfig.targets

  test "Node config has search configuration":
    let configs = loadConfigFile(builtinConfigPath)

    var nodeConfig: ProjectConfig
    for c in configs:
      if c.name == "node" and c.configType == ctProject:
        nodeConfig = c
        break

    check nodeConfig.search.isSome == true
    let search = nodeConfig.search.get()
    check search.searchType == stRecursive
    check search.base == "~"
    check search.maxDepth == 3
    check search.recursiveTarget == "node_modules"
    echo "Search type: ", search.searchType
    echo "Recursive target: ", search.recursiveTarget
    echo "Min age: ", search.recursiveMinAge
    echo "Skip: ", search.skip
    echo "Skip hidden: ", search.recursiveSkipHidden

  test "Scan node_modules directories":
    let configs = loadConfigFile(builtinConfigPath)

    var nodeConfig: ProjectConfig
    for c in configs:
      if c.name == "node" and c.configType == ctProject:
        nodeConfig = c
        break

    echo "\nScanning for node_modules directories..."
    echo "Base: ", nodeConfig.search.get().base
    echo "Max depth: ", nodeConfig.search.get().maxDepth
    echo "Target: ", nodeConfig.search.get().recursiveTarget

    let results = scanProject(nodeConfig)

    echo "\nFound ", results.len, " node_modules directories:"
    var totalSize: int64 = 0
    for r in results:
      echo "  - ", r.dir, ": ", r.size
      totalSize += r.size
    echo "\nTotal size: ", totalSize

  test "Check shouldShowDirective for node":
    let configs = loadConfigFile(builtinConfigPath)

    var nodeConfig: ProjectConfig
    for c in configs:
      if c.name == "node" and c.configType == ctProject:
        nodeConfig = c
        break

    echo "\nNode config:"
    echo "  toolBin: '", nodeConfig.toolBin, "'"
    echo "  has search: ", nodeConfig.search.isSome

    let shouldShow = shouldShowDirective(nodeConfig)
    echo "  shouldShowDirective: ", shouldShow

    # Node has no tool_bin but has search config, should now show
    check shouldShow == true
