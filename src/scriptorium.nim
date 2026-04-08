import
  std/[os, strformat, strutils],
  ./scriptorium/[audit_agent_cli, config, dashboard, discord_bot, init, mattermost_bot, orchestrator, output_formatting, remote_sync]

const
  Version = "19.5.0"
  Usage = """scriptorium - agent orchestration system

Usage:
  scriptorium init [path]      Initialize a new scriptorium workspace
  scriptorium --init [path]    Alias for init
  scriptorium run              Start the orchestrator daemon
  scriptorium status           Show ticket counts and agent activity
  scriptorium plan             Interactive Architect conversation to build/revise spec.md
  scriptorium plan <prompt>    One-shot: ask the Architect to revise spec.md
  scriptorium ask              Interactive read-only Q&A session with the Architect
  scriptorium do               Interactive coding session with full repo access
  scriptorium do <prompt>      One-shot: run an ad-hoc task with full repo access
  scriptorium audit            Run the audit agent
  scriptorium dashboard        Start the web dashboard
  scriptorium discord          Run the Discord bot
  scriptorium mattermost       Run the Mattermost bot
  scriptorium sync             Run a single remote sync cycle (fetch/merge/push)
  scriptorium worktrees        List active git worktrees and their tickets
  scriptorium --version        Print version
  scriptorium --help           Show this help"""
  WorktreesHeader = "WORKTREE\tTICKET\tBRANCH"

proc cmdInit(path: string) =
  ## Initialize a new scriptorium workspace at the given path.
  runInit(path)

proc cmdRun() =
  ## Start the orchestrator daemon.
  runOrchestrator(getCurrentDir())

proc cmdStatus() =
  ## Show ticket counts, agent activity, elapsed times, recent done tickets, and first-attempt success rate.
  let status = readOrchestratorStatus(getCurrentDir(), PlanCallerCli)
  echo fmt"Open: {status.openTickets}"
  echo fmt"In Progress: {status.inProgressTickets}"
  echo fmt"Done: {status.doneTickets}"
  if status.activeTicketId.len == 0:
    echo "Active Agent: none"
  else:
    echo fmt"Active Agent Ticket: {status.activeTicketId} ({status.activeTicketPath})"
    echo fmt"Active Agent Branch: {status.activeTicketBranch}"
    if status.activeTicketWorktree.len > 0:
      echo fmt"Active Agent Worktree: {status.activeTicketWorktree}"
    else:
      echo "Active Agent Worktree: unknown"
  for item in status.inProgressElapsed:
    echo fmt"In-Progress Ticket {item.ticketId}: elapsed {item.elapsed}"
  if status.recentDoneTickets.len > 0:
    echo ""
    echo "Recent Completed Tickets:"
    for item in status.recentDoneTickets:
      let wallDuration = formatDuration(item.wallTimeSeconds.float)
      echo fmt"  {item.ticketId}: outcome={item.outcome}, wall={wallDuration}"
  if status.totalDoneWithAttempts > 0:
    let pct = (status.firstAttemptSuccessCount * 100) div status.totalDoneWithAttempts
    echo fmt"First-attempt success: {pct}% ({status.firstAttemptSuccessCount}/{status.totalDoneWithAttempts})"
  for item in status.blockedTickets:
    let cycleList = item.cycleIds.join(", ")
    echo fmt"Blocked: {item.ticketId} (circular dependency with {cycleList})"
  for item in status.waitingTickets:
    let depList = item.dependsOn.join(", ")
    echo fmt"Waiting: {item.ticketId} (depends on {depList})"

proc cmdPlan(args: seq[string]) =
  ## Ask the architect model to revise spec.md, interactively or one-shot.
  if args.len == 0:
    runInteractivePlanSession(getCurrentDir())
  else:
    let prompt = args.join(" ").strip()
    let changed = updateSpecFromArchitect(getCurrentDir(), PlanCallerCli, prompt)
    if changed:
      echo "scriptorium: updated spec.md on scriptorium/plan"
    else:
      echo "scriptorium: spec.md unchanged"

proc cmdAsk() =
  ## Start a read-only Q&A session with the Architect.
  runInteractiveAskSession(getCurrentDir())

proc cmdDo(args: seq[string]) =
  ## Run the architect as a coding agent with full repo access.
  if args.len == 0:
    runInteractiveDoSession(getCurrentDir())
  else:
    let prompt = args.join(" ").strip()
    runOneShotDoSession(getCurrentDir(), prompt)

proc cmdAudit() =
  ## Run the audit agent against the current repository.
  runAudit(getCurrentDir())

proc cmdDashboard() =
  ## Start the web dashboard HTTP server.
  runDashboard(getCurrentDir())

proc cmdDiscord() =
  ## Run the Discord bot.
  runDiscordBot(getCurrentDir())

proc cmdMattermost() =
  ## Run the Mattermost bot.
  runMattermostBot(getCurrentDir())

proc cmdSync() =
  ## Run a single remote sync cycle: fetch, merge from primary, push to all.
  let repoPath = getCurrentDir()
  let cfg = loadConfig(repoPath)
  if not cfg.remoteSync.enabled:
    echo "scriptorium: remote sync is not enabled in scriptorium.json"
    quit(1)
  let syncResult = syncRemotes(repoPath, cfg.remoteSync)
  echo fmt"Fetched: {syncResult.fetchedRemotes} remotes ({syncResult.fetchFailures} failures)"
  echo fmt"Merge: {syncResult.mergeResult}"
  echo fmt"Pushed: {syncResult.pushedRemotes} remotes ({syncResult.pushFailures} failures)"

proc cmdWorktrees() =
  ## List active git worktrees and which tickets they belong to.
  let worktrees = listActiveTicketWorktrees(getCurrentDir(), PlanCallerCli)
  if worktrees.len == 0:
    echo "scriptorium: no active ticket worktrees"
  else:
    echo WorktreesHeader
    for item in worktrees:
      echo item.worktree & "\t" & item.ticketId & "\t" & item.branch

proc loadDotEnv() =
  ## Load .env file from the current directory if it exists. Does not override existing env vars.
  let path = getCurrentDir() / ".env"
  if not fileExists(path):
    return
  for line in lines(path):
    let stripped = line.strip()
    if stripped.len == 0 or stripped[0] == '#':
      continue
    let eqPos = stripped.find('=')
    if eqPos < 1:
      continue
    let key = stripped[0 ..< eqPos].strip()
    var val = stripped[eqPos + 1 .. ^1].strip()
    # Strip surrounding quotes.
    if val.len >= 2 and val[0] == '"' and val[^1] == '"':
      val = val[1 ..< ^1]
    if getEnv(key).len == 0:
      putEnv(key, val)

when isMainModule:
  loadDotEnv()
  let args = commandLineParams()

  if args.len == 0:
    echo Usage
    quit(0)

  case args[0]
  of "run":
    cmdRun()
  of "status":
    cmdStatus()
  of "plan":
    let planArgs = if args.len > 1: args[1..^1] else: @[]
    cmdPlan(planArgs)
  of "ask":
    cmdAsk()
  of "do":
    let doArgs = if args.len > 1: args[1..^1] else: @[]
    cmdDo(doArgs)
  of "dashboard":
    cmdDashboard()
  of "audit":
    cmdAudit()
  of "discord":
    cmdDiscord()
  of "mattermost":
    cmdMattermost()
  of "sync":
    cmdSync()
  of "worktrees":
    cmdWorktrees()
  of "init":
    let path = if args.len > 1: args[1] else: ""
    cmdInit(path)
  of "--init":
    stderr.writeLine "Warning: --init is deprecated, use `scriptorium init` instead."
    let path = if args.len > 1: args[1] else: ""
    cmdInit(path)
  of "--version":
    echo Version
  of "--help", "-h":
    echo Usage
  else:
    echo fmt"scriptorium: unknown command '{args[0]}'"
    echo Usage
    quit(1)
