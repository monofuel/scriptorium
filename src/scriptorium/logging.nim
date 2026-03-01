## Global file logger for scriptorium orchestrator sessions.

import
  std/[os, strformat, times]

type
  LogLevel* = enum
    lvlDebug, lvlInfo, lvlWarn, lvlError

const
  LogLevelLabels: array[LogLevel, string] = ["DEBUG", "INFO", "WARN", "ERROR"]
  LogDirBase = "/tmp/scriptorium"

var
  logFile: File
  logFilePath*: string
  logInitialized: bool
  minLogLevel*: LogLevel = lvlInfo

proc formatTimestamp(): string =
  ## Return a UTC timestamp suitable for log line prefixes.
  result = now().utc().format("yyyy-MM-dd'T'HH:mm:ss'Z'")

proc formatFileTimestamp(): string =
  ## Return a UTC timestamp suitable for log file names.
  result = now().utc().format("yyyy-MM-dd'T'HH-mm-ss'Z'")

proc initLog*(repoPath: string) =
  ## Create the session log file and open it for writing.
  let projectName = lastPathPart(repoPath)
  let logDir = LogDirBase / projectName
  createDir(logDir)
  logFilePath = logDir / fmt"run_{formatFileTimestamp()}.log"
  logFile = open(logFilePath, fmWrite)
  logInitialized = true

proc closeLog*() =
  ## Flush and close the log file handle.
  if logInitialized:
    flushFile(logFile)
    close(logFile)
    logInitialized = false

proc setLogLevel*(level: LogLevel) =
  ## Set the minimum log level for stdout output.
  minLogLevel = level

proc log*(level: LogLevel, msg: string) =
  ## Write a timestamped log line to stdout (filtered) and the log file (always).
  let line = fmt"[{formatTimestamp()}] [{LogLevelLabels[level]}] {msg}"
  if level >= minLogLevel:
    echo line
  if logInitialized:
    writeLine(logFile, line)
    flushFile(logFile)

proc logDebug*(msg: string) =
  ## Log a message at debug level.
  log(lvlDebug, msg)

proc logInfo*(msg: string) =
  ## Log a message at info level.
  log(lvlInfo, msg)

proc logWarn*(msg: string) =
  ## Log a message at warn level.
  log(lvlWarn, msg)

proc logError*(msg: string) =
  ## Log a message at error level.
  log(lvlError, msg)
