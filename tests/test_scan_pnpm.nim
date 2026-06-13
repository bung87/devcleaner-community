import std/[unittest, os, options, strutils]
import devcleaner/[config_parser, types, scanner, utils, constants]

suite "pnpm Config Scan Tests":
  test "Load pnpm config from builtin":
    let configs = parseConfig(BuiltinConfigContent)

    var pnpmConfig: TaskConfig
    var found = false
    for c in configs:
      if c.name == "pnpm" and c.configType == ctProject:
        pnpmConfig = c
        found = true
        break

    check found == true
    check pnpmConfig.name == "pnpm"
    check pnpmConfig.configType == ctProject
    check pnpmConfig.bin == @["pnpm"]
    check pnpmConfig.search.isSome == true

  test "pnpm config has search configuration":
    let configs = parseConfig(BuiltinConfigContent)

    var pnpmConfig: TaskConfig
    for c in configs:
      if c.name == "pnpm" and c.configType == ctProject:
        pnpmConfig = c
        break

    check pnpmConfig.search.isSome == true
    let search = pnpmConfig.search.get()
    check search.searchType == stStatic
    check search.staticDirs.len >= 1
    echo "pnpm dirs: ", search.staticDirs
