import std/[unittest, os, options]
import ../src/[config_loader, types, scanner]

suite "All Configs Scan Test":
  test "Load all configs and check which have search":
    let configs = loadConfigFile(ConfigPath)
    
    echo "\nAll configs:"
    for c in configs:
      let hasSearch = if c.search.isSome: "YES" else: "NO"
      let searchType = if c.search.isSome: $c.search.get().searchType else: "N/A"
      echo "  - ", c.name, " (", c.configType, ") - search: ", hasSearch, " type: ", searchType
  
  test "Scan all configs with search":
    let configs = loadConfigFile(builtinConfigPath)
    
    echo "\nScanning all configs with search:"
    for c in configs:
      if c.search.isSome:
        echo "\nScanning ", c.name, "..."
        let results = scanProject(c)
        echo "  Found ", results.len, " directories"
        for r in results:
          echo "    - ", r.dir
