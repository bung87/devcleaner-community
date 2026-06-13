import std/[unittest, os, options, strutils]
import ../src/[config_loader, types, scanner, utils, constants]

suite "Mac Config Scan Tests":
  test "Load mac config from builtin":
    let configs = loadConfigFile(ConfigPath)

    var macConfig: TaskConfig
    var found = false
    for c in configs:
      if c.name == "mac" and c.configType == ctSystem:
        macConfig = c
        found = true
        break

    check found == true
    check macConfig.name == "mac"
    check macConfig.configType == ctSystem
    echo "Mac config found:"
    echo "  name: ", macConfig.name
    echo "  has search: ", macConfig.search.isSome

  test "Mac config has search configuration":
    let configs = loadConfigFile(builtinConfigPath)

    var macConfig: ProjectConfig
    for c in configs:
      if c.name == "mac" and c.configType == ctSystem:
        macConfig = c
        break

    check macConfig.search.isSome == true
    let search = macConfig.search.get()
    check search.searchType == stStatic
    echo "Search config:"
    echo "  type: ", search.searchType
    echo "  staticDirs: ", search.staticDirs

  test "Scan mac system caches":
    let configs = loadConfigFile(builtinConfigPath)

    var macConfig: ProjectConfig
    for c in configs:
      if c.name == "mac" and c.configType == ctSystem:
        macConfig = c
        break

    echo "\nScanning mac system caches..."
    let results = scanProject(macConfig)

    echo "Found ", results.len, " cache directories:"
    var totalSize: int64 = 0
    for r in results:
      echo "  - ", r.dir, ": ", r.size
      totalSize += r.size
    echo "\nTotal size: ", totalSize

  test "Mac shouldShowDirective always returns true":
    let configs = loadConfigFile(builtinConfigPath)

    var macConfig: ProjectConfig
    for c in configs:
      if c.name == "mac" and c.configType == ctSystem:
        macConfig = c
        break

    # System directives should always show
    check shouldShowDirective(macConfig) == true
    echo "shouldShowDirective(mac) = ", shouldShowDirective(macConfig)
