import ../src/[config_loader, types, utils]

proc main() =
  echo "=== Tasks that will be created ==="
  echo ""

  let configs = loadConfigFile(ConfigPath)

  var taskCount = 0

  for config in configs:
    if not shouldShowDirective(config):
      continue

    taskCount += 1
    let typeStr = if config.configType == ctSystem: "system" else: "project"
    echo taskCount, ". ", config.name, " (", typeStr, ")"

  echo ""
  echo "Total: ", taskCount, " tasks will be created"

when isMainModule:
  main()
