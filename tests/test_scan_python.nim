import std/[unittest, os, options, strutils]
import ../src/[config_loader, types, scanner, constants]

suite "Python Config Scan Tests":
  test "Load python config from builtin":
    let configs = loadConfigFile(ConfigPath)
    
    # Find python config
    var pythonConfig: TaskConfig
    var found = false
    for c in configs:
      if c.name == "python" and c.configType == ctProject:
        pythonConfig = c
        found = true
        break
    
    check found == true
    check pythonConfig.name == "python"
    check pythonConfig.configType == ctProject
    check pythonConfig.bin == "python"
    check pythonConfig.markers.len > 0
    echo "Python markers: ", pythonConfig.markers
    check pythonConfig.targets.len > 0
    echo "Python targets: ", pythonConfig.targets
  
  test "Python config has search configuration":
    let configs = loadConfigFile(builtinConfigPath)
    
    var pythonConfig: ProjectConfig
    for c in configs:
      if c.name == "python" and c.configType == ctProject:
        pythonConfig = c
        break
    
    check pythonConfig.search.isSome == true
    let search = pythonConfig.search.get()
    check search.searchType == stVirtualenv
    check search.base == "~"
    check search.maxDepth == 3
    echo "Search type: ", search.searchType
    echo "Venv markers: ", search.venvMarkers
    echo "Venv skip_at_root: ", search.venvSkipAtRoot
    echo "Venv allow_hidden: ", search.venvAllowHidden
  
  test "Scan python virtualenvs":
    let configs = loadConfigFile(builtinConfigPath)
    
    var pythonConfig: ProjectConfig
    for c in configs:
      if c.name == "python" and c.configType == ctProject:
        pythonConfig = c
        break
    
    echo "Scanning for python virtualenvs..."
    echo "Base: ", pythonConfig.search.get().base
    echo "Max depth: ", pythonConfig.search.get().maxDepth
    echo "Venv markers: ", pythonConfig.search.get().venvMarkers
    
    let results = scanProject(pythonConfig)
    
    echo "Found ", results.len, " virtualenvs"
    for r in results:
      echo "  - ", r.dir, ": ", r.size
  
  test "Check home directory for virtualenvs manually":
    # Let's manually check if there are any .venv directories
    let home = expandTilde("~")
    echo "Checking home directory: ", home
    
    var foundVenvs: seq[string] = @[]
    for kind, path in walkDir(home):
      if kind == pcDir:
        let name = extractFilename(path)
        # Check for .venv or venv in subdirectories
        for subKind, subPath in walkDir(path):
          if subKind == pcDir:
            let subName = extractFilename(subPath)
            if subName == ".venv" or subName == "venv":
              echo "Found potential venv: ", subPath
              # Check if it has bin/python
              if fileExists(subPath / "bin" / "python"):
                echo "  -> Has bin/python"
                foundVenvs.add(subPath)
              elif fileExists(subPath / "bin" / "python3"):
                echo "  -> Has bin/python3"
                foundVenvs.add(subPath)
    
    echo "Total venvs found: ", foundVenvs.len
