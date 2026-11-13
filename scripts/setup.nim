import
  std/[os, osproc, strtabs, strutils]

proc main() =
  ## Install locked Nim packages privately and regenerate compiler search paths.
  let
    root = getCurrentDir()
    dependencyHome = root / ".build" / "nimby"
    workspace = dependencyHome / "workspace"
    environment = newStringTable(modeCaseSensitive)
  for key, value in envPairs(): environment[key] = value
  environment["NIMBY_HOME"] = dependencyHome
  createDir(dependencyHome)
  createDir(workspace)
  writeFile(workspace / "nim.cfg", "# Managed by Nimby\n")
  let process = startProcess("nimby", workingDir = workspace,
    args = @["sync", "-g", root / "nimby.lock"],
    env = environment, options = {poUsePath, poParentStreams})
  let exitCode = process.waitForExit()
  process.close()
  if exitCode != 0: quit(exitCode)
  var paths = ""
  for line in lines(root / "nimby.lock"):
    let fields = line.splitWhitespace()
    if fields.len == 0: continue
    let directory = dependencyHome / "pkgs" / fields[0]
    let installed = execProcess("git", args = @["-C", directory, "rev-parse", "HEAD"],
      options = {poUsePath}).strip()
    if installed != fields[3]:
      raise newException(ValueError, "Installed dependency differs from lockfile: " &
        fields[0] & "; expected " & fields[3] & "; got " & installed)
    paths.add("--path:" & escape(directory) & "\n")
    if dirExists(directory / "src"):
      paths.add("--path:" & escape(directory / "src") & "\n")
  writeFile(root / "nim.cfg", paths)

main()
