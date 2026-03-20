# Nim Process Creation and Threads: The `osproc` Double-Close Bug

## Summary

Nim 2.2.4's `osproc.startProcess` with `poStdErrToStdOut` causes a double-close
of the stdout file descriptor in `process.close()`. In multi-threaded programs,
this creates a race condition where one thread's `close()` can destroy another
thread's pipe file descriptor.

## The Bug

When `poStdErrToStdOut` is passed to `startProcess`, the implementation sets:

```nim
# nim/lib/pure/osproc.nim, lines 1034-1036
if poStdErrToStdOut in options:
  data.options.add(poStdErrToStdOut)
  errHandle = outHandle  # <-- both point to the same fd
```

Later, `process.close()` closes handles independently:

```nim
# nim/lib/pure/osproc.nim, lines 1188-1203
proc close(p: Process) =
  ...
  if p.outHandle != 0:
    discard close(p.outHandle)  # first close of fd N
  if p.errHandle != 0:
    discard close(p.errHandle)  # second close of fd N (same fd!)
```

Since `errHandle == outHandle`, the same fd is closed twice.

## The Race Condition

The double-close is benign in single-threaded programs. In multi-threaded
programs, it creates a dangerous race:

```
Thread A                          Thread B
--------                          --------
startProcess() → gets fd 7
  (outHandle=7, errHandle=7)
readAll() on fd 7
waitForExit()
close(outHandle=7)                pipe() → kernel reuses fd 7
close(errHandle=7) ← closes       for Thread B's new pipe
  Thread B's pipe!
                                  readAll() on fd 7 → EBADF!
```

The POSIX kernel always assigns the lowest available file descriptor number.
After Thread A's first `close(7)`, fd 7 becomes available. Thread B's `pipe()`
call reuses it. Thread A's second `close(7)` then destroys Thread B's pipe.

## Symptoms

- `Bad file descriptor` errors on `outputStream` reads
- Sporadic, non-deterministic — depends on exact thread scheduling
- More likely under load with many concurrent process spawns
- Adding debug logging (which serializes I/O) can mask the race

## The Fix: `processLock`

Scriptorium uses a global `Lock` to serialize all `startProcess` + `close()`
pairs, preventing any `pipe()` from running during the double-close window.

### Short-lived processes (git commands)

Hold the lock for the entire process lifetime:

```nim
acquireProcessLock()
let process = startProcess("git", args = allArgs,
                           options = {poUsePath, poStdErrToStdOut})
let output = process.outputStream.readAll()
let rc = process.waitForExit(timeoutMs)
process.close()
releaseProcessLock()
```

### Long-running processes (make test, etc.)

Lock only around `startProcess` and `close()`, not during `readAll`/`waitForExit`:

```nim
acquireProcessLock()
let process = startProcess(command, workingDir = workingDir,
                           args = args,
                           options = {poUsePath, poStdErrToStdOut})
discard process.outputStream  # force stream initialization while locked
releaseProcessLock()

# These run without the lock — safe because the fd is in use
let output = process.outputStream.readAll()
let exitCode = process.waitForExit(timeoutMs)

acquireProcessLock()
process.close()  # double-close happens here, must be serialized
releaseProcessLock()
```

The key insight for the split-lock pattern: `readAll()` and `waitForExit()` are
safe to call without the lock because the fd is actively in use (open and being
read from), so the kernel won't reuse it. The dangerous window is only during
`close()`, when the fd is freed and then freed again.

## Additional Notes

- On Linux, Nim uses `fork()` (not `posix_spawn`), and pipes are created without
  `O_CLOEXEC`, which is another potential concern for fd leaks into child
  processes — but separate from the double-close issue.
- The proper fix in Nim's stdlib would be to skip the second close when
  `errHandle == outHandle`. Until that's fixed upstream, the lock is necessary.
- The `{.cast(gcsafe).}` annotation is needed because the lock is a global
  variable accessed from spawned threads.

## References

- Nim 2.2.4 source: `lib/pure/osproc.nim`
- Scriptorium fix: `src/scriptorium/git_ops.nim` (`processLock`)
