import
  std/[locks, os, osproc, strtabs]

when defined(posix):
  import
    std/posix

var processCreationLock: Lock

initLock(processCreationLock)

proc acquireProcessCreationLock*() =
  ## Acquire the process-creation lock shared by all harnesses.
  {.cast(gcsafe).}:
    acquire(processCreationLock)

proc releaseProcessCreationLock*() =
  ## Release the process-creation lock shared by all harnesses.
  {.cast(gcsafe).}:
    release(processCreationLock)

proc markCloseOnExec(handle: FileHandle) =
  ## Prevent one managed child from retaining another child's parent-side pipe.
  when defined(posix):
    let descriptor = cint(handle)
    if descriptor >= 0:
      let flags = fcntl(descriptor, F_GETFD)
      if flags < 0 or fcntl(descriptor, F_SETFD, flags or FD_CLOEXEC) < 0:
        raiseOSError(osLastError())

proc startProcessGuarded*(command: string, workingDir = "",
    args: openArray[string] = [], env: StringTableRef = nil,
    options: set[ProcessOption] = {poStdErrToStdOut}): Process =
  ## Start one process without leaking transient descriptors into another child.
  acquireProcessCreationLock()
  try:
    result = startProcess(command, workingDir, args, env, options)
    result.inputHandle.markCloseOnExec()
    result.outputHandle.markCloseOnExec()
    result.errorHandle.markCloseOnExec()
  finally:
    releaseProcessCreationLock()
