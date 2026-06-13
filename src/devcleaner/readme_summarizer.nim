import std/[os, strutils, json, options, algorithm]
import chronicles

## README Summarizer Module - Apple Intelligence + Local Fallback
##
## This module provides project description extraction using:
## 1. Apple Intelligence (via Shortcuts) - Primary method
## 2. Local file parsing - Fallback method
##
## Supported project files:
## - package.json (Node.js)
## - Cargo.toml (Rust)
## - pubspec.yaml (Flutter/Dart)
## - README files

proc findReadme*(projectDir: string): Option[string] =
  ## Find README file in project directory
  let readmeVariants = @[
    "README.md", "README.txt", "README",
    "readme.md", "readme.txt", "readme",
    "Readme.md", "Readme.txt", "Readme"
  ]

  for variant in readmeVariants:
    let path = projectDir / variant
    if fileExists(path):
      return some(path)

  return none(string)

proc extractFirstParagraph*(content: string): string =
  ## Extract first meaningful paragraph from README content
  let lines = content.splitLines()
  var paragraph: seq[string] = @[]
  var inCodeBlock = false

  for line in lines:
    let trimmed = line.strip()

    if trimmed.startswith("```"):
      inCodeBlock = not inCodeBlock
      continue
    if inCodeBlock:
      continue

    if trimmed.len == 0:
      if paragraph.len > 0:
        break
      continue

    if trimmed.startswith("#"):
      continue

    # Filter out markdown images: ![alt](url) - covers all badges and images
    if trimmed.startswith("![") and ("](" in trimmed or "]( " in trimmed):
      continue
    
    # Filter out linked images: [![alt](image)](link) - common for badges
    if trimmed.startswith("[![") and ("](" in trimmed or "]( " in trimmed):
      continue
    
    # Filter out HTML img tags
    if trimmed.startswith("<") and ("img" in trimmed.toLower() or "src=" in trimmed):
      continue

    if trimmed.startswith("<") and ">" in trimmed:
      continue

    if trimmed.toLower() in ["table of contents", "toc", "contents"]:
      continue

    paragraph.add(trimmed)

    if paragraph.len >= 5:
      break

  result = paragraph.join(" ")
  # Collapse multiple whitespace into single space
  while result.contains("  "):
    result = result.replace("  ", " ")
  result = result.strip()

  if result.len > 200:
    result = result[0..200] & "..."

proc extractFromPackageJson*(projectDir: string): string =
  ## Extract description from package.json for Node.js projects
  let packagePath = projectDir / "package.json"
  if not fileExists(packagePath):
    return ""

  try:
    let content = readFile(packagePath)
    let json = parseJson(content)

    if json.hasKey("description"):
      let desc = json["description"].getStr()
      if desc.len > 0:
        return desc

  except:
    debug "Failed to parse package.json", path = packagePath

  return ""

proc extractFromCargoToml*(projectDir: string): string =
  ## Extract description from Cargo.toml for Rust projects
  let cargoPath = projectDir / "Cargo.toml"
  if not fileExists(cargoPath):
    return ""

  try:
    let content = readFile(cargoPath)
    var inPackageSection = false

    for line in content.splitLines():
      let trimmed = line.strip()

      if trimmed == "[package]":
        inPackageSection = true
        continue

      if trimmed.startswith("[") and trimmed.endswith("]") and trimmed != "[package]":
        inPackageSection = false
        continue

      if inPackageSection:
        if trimmed.startswith("description") and "=" in trimmed:
          let parts = trimmed.split("=", maxsplit=1)
          if parts.len == 2:
            var desc = parts[1].strip()
            if desc.startswith("\"") and desc.endswith("\""):
              desc = desc[1..^2]
            if desc.len > 0:
              return desc

        if trimmed.startswith("name") and "=" in trimmed:
          let parts = trimmed.split("=", maxsplit=1)
          if parts.len == 2:
            var name = parts[1].strip()
            if name.startswith("\"") and name.endswith("\""):
              name = name[1..^2]
            if name.len > 0:
              return "Rust project: " & name
  except:
    debug "Failed to parse Cargo.toml", path = cargoPath

  return ""

proc extractFromPubspecYaml*(projectDir: string): string =
  ## Extract description from pubspec.yaml for Flutter/Dart projects
  let pubspecPath = projectDir / "pubspec.yaml"
  if not fileExists(pubspecPath):
    return ""

  try:
    let content = readFile(pubspecPath)
    var foundName = ""

    for line in content.splitLines():
      let trimmed = line.strip()

      if trimmed.startswith("description:"):
        let parts = trimmed.split(":", maxsplit=1)
        if parts.len == 2:
          var desc = parts[1].strip()
          if desc.len > 0:
            return desc

      if trimmed.startswith("name:"):
        let parts = trimmed.split(":", maxsplit=1)
        if parts.len == 2:
          foundName = parts[1].strip()

    if foundName.len > 0:
      return "Flutter/Dart project: " & foundName
  except:
    debug "Failed to parse pubspec.yaml", path = pubspecPath

  return ""

proc summarizeProject*(projectDir: string): string =
  ## Generate a summary for a project using Apple Intelligence first,
  ## then falling back to local file parsing

  result = ""

  # First, try to get README content for Apple Intelligence
  let readmePath = findReadme(projectDir)
  if readmePath.isSome:
    # try:
    #   let readmeContent = readFile(readmePath.get)
    #   if readmeContent.len > 0:
    #     # Try Apple Intelligence first
    #     result = getProjectSummaryWithAI(readmeContent)
    #     if result.len > 0:
    #       debug "Using Apple Intelligence summary", dir = projectDir
    #       return result
    # except:
    #   debug "Failed to read README for AI summarization", path = readmePath.get
    try:
      let content = readFile(readmePath.get)
      result = extractFirstParagraph(content)
      if result.len > 0:
        return result
    except:
      debug "Failed to read README", path = readmePath.get
  # Fall back to local file parsing
  debug "Falling back to local parsing", dir = projectDir

  result = extractFromPackageJson(projectDir)
  if result.len > 0:
    return result

  result = extractFromCargoToml(projectDir)
  if result.len > 0:
    return result

  result = extractFromPubspecYaml(projectDir)
  if result.len > 0:
    return result

  return ""

proc generateFileTree*(projectDir: string; maxDepth: int = 3; prefix: string = ""): string =
  ## Generate a tree-like directory listing similar to Unix 'tree' command
  ## Returns a string representation of the directory structure
  
  if not dirExists(projectDir):
    return ""
  
  var lines: seq[string] = @[]
  let dirName = extractFilename(projectDir)
  if prefix.len == 0:
    lines.add(dirName)
  
  try:
    var entries: seq[tuple[name: string, isDir: bool]] = @[]
    
    for kind, path in walkDir(projectDir):
      let name = extractFilename(path)
      # Skip hidden files and common non-essential directories
      if name.startswith("."):
        continue
      if name in ["node_modules", "target", "build", "dist", "__pycache__", ".git", ".svn", ".hg", "nimcache", ".nimble", "zig-cache", "zig-out"]:
        continue
      entries.add((name, kind == pcDir))
    
    # Sort entries: directories first, then files
    proc compareEntries(a, b: tuple[name: string, isDir: bool]): int =
      if a.isDir and not b.isDir: return -1
      if not a.isDir and b.isDir: return 1
      return cmp(a.name, b.name)
    
    entries.sort(compareEntries)
    
    let currentDepth = prefix.len div 4
    if currentDepth >= maxDepth:
      if entries.len > 0:
        lines.add(prefix & "`-- ...")
      return lines.join("\n")
    
    for i, entry in entries:
      let isLast = i == entries.len - 1
      let connector = if isLast: "`-- " else: "|-- "
      let line = prefix & connector & entry.name
      lines.add(line)
      
      if entry.isDir:
        let subPath = projectDir / entry.name
        let newPrefix = prefix & (if isLast: "    " else: "|   ")
        let subTree = generateFileTree(subPath, maxDepth, newPrefix)
        if subTree.len > 0:
          # Skip the directory name since we already added it
          let subLines = subTree.splitLines()
          if subLines.len > 1:
            for j in 1..<subLines.len:
              lines.add(subLines[j])
    
  except:
    debug "Failed to generate file tree", dir = projectDir
  
  return lines.join("\n")

proc getProjectDescription*(projectDir: string): string =
  ## Convenience function to get project description.
  ## Falls back to file tree if no description can be extracted.
  result = summarizeProject(projectDir)
