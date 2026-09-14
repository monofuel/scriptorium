import
  std/[osproc, posix, streams, unittest],
  scriptorium/process_lock

suite "process creation lock":
  test "marks parent-side child pipes close-on-exec":
    let process = startProcessGuarded(
      "sh",
      args = @["-c", "cat >/dev/null"],
      options = {poUsePath, poStdErrToStdOut},
    )
    defer:
      process.close()

    let
      inputFlags = fcntl(cint(process.inputHandle), F_GETFD)
      outputFlags = fcntl(cint(process.outputHandle), F_GETFD)
    check inputFlags >= 0
    check outputFlags >= 0
    check (inputFlags and FD_CLOEXEC) != 0
    check (outputFlags and FD_CLOEXEC) != 0

    process.inputStream.close()
    discard process.outputStream.readAll()
    check process.waitForExit() == 0
