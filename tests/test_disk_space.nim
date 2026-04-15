import
  scriptorium/orchestrator

proc testAvailableDiskSpaceGBReturnsPositive() =
  ## Verify availableDiskSpaceGB returns a positive value for the root filesystem.
  let gb = availableDiskSpaceGB("/")
  doAssert gb > 0.0, "availableDiskSpaceGB should return a positive value"
  echo "[OK] availableDiskSpaceGB returns positive value: " & $gb & " GB"

proc testAvailableDiskSpaceGBInvalidPath() =
  ## Verify availableDiskSpaceGB raises OSError for a nonexistent path.
  var raised = false
  try:
    discard availableDiskSpaceGB("/nonexistent_path_that_should_not_exist_abc123")
  except OSError:
    raised = true
  doAssert raised, "availableDiskSpaceGB should raise OSError for invalid path"
  echo "[OK] availableDiskSpaceGB raises OSError for invalid path"

when isMainModule:
  testAvailableDiskSpaceGBReturnsPositive()
  testAvailableDiskSpaceGBInvalidPath()
