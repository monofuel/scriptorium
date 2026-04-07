## Global file logger for scriptorium sessions.

import
  std/[os, strformat, strutils, times],
  ./config

type
  LogLevel* = enum
    lvlDebug, lvlInfo, lvlWarn, lvlError

const
  LogLevelLabels: array[LogLevel, string] = ["DEBUG", "INFO", "WARN", "ERROR"]

type
  CapturedLog* = tuple[level: LogLevel, msg: string]

var
  logFile: File
  logFilePath*: string
  logInitialized: bool
  minLogLevel*: LogLevel = lvlInfo
  minFileLogLevel*: LogLevel = lvlDebug
  capturedLogs*: seq[CapturedLog]
  captureLogs*: bool

proc formatTimestamp(): string =
  ## Return a UTC timestamp suitable for log line prefixes.
  result = now().utc().format("yyyy-MM-dd'T'HH:mm:ss'Z'")

proc formatFileTimestamp(): string =
  ## Return a UTC timestamp suitable for log file names.
  result = now().utc().format("yyyy-MM-dd'T'HH-mm-ss'Z'")

proc initLog*(repoPath: string, subdirectory: string = "orchestrator") =
  ## Create the session log file and open it for writing.
  let logDir = repoPath / ".scriptorium" / "logs" / subdirectory
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

proc setFileLogLevel*(level: LogLevel) =
  ## Set the minimum log level for log file output.
  minFileLogLevel = level

proc log*(level: LogLevel, msg: string) =
  ## Write a timestamped log line to stdout (filtered) and the log file (always).
  if captureLogs:
    capturedLogs.add((level: level, msg: msg))
  let line = fmt"[{formatTimestamp()}] [{LogLevelLabels[level]}] {msg}"
  if level >= minLogLevel:
    echo line
  if logInitialized and level >= minFileLogLevel:
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

proc parseLogLevel*(value: string): LogLevel =
  ## Parse a log level string into a LogLevel enum value.
  case value.toLowerAscii()
  of "debug": lvlDebug
  of "info": lvlInfo
  of "warn", "warning": lvlWarn
  of "error": lvlError
  else:
    raise newException(ValueError, &"unknown log level: {value}")

proc applyLogLevelFromConfig*(repoPath: string) =
  ## Apply log level settings from the project config file.
  let cfg = loadConfig(repoPath)
  if cfg.logLevel.len > 0:
    try:
      setLogLevel(parseLogLevel(cfg.logLevel))
    except ValueError:
      logWarn(&"unknown log level '{cfg.logLevel}', using default")
  if cfg.fileLogLevel.len > 0:
    try:
      setFileLogLevel(parseLogLevel(cfg.fileLogLevel))
    except ValueError:
      logWarn(&"unknown file log level '{cfg.fileLogLevel}', using default")
