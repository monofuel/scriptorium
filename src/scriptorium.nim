import
  std/[os, strformat, strutils],
  ./scriptorium/[init, orchestrator, output_formatting]

const
  Version = "0.1.0"
  Usage = """scriptorium - agent orchestration system

Usage:
  scriptorium --init [path]    Initialize a new scriptorium workspace
  scriptorium run              Start the orchestrator daemon
  scriptorium status           Show ticket counts and agent activity
  scriptorium plan             Interactive Architect conversation to build/revise spec.md
  scriptorium plan <prompt>    One-shot: ask the Architect to revise spec.md
  scriptorium ask              Interactive read-only Q&A session with the Architect
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
  let status = readOrchestratorStatus(getCurrentDir())
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
    let changed = updateSpecFromArchitect(getCurrentDir(), prompt)
    if changed:
      echo "scriptorium: updated spec.md on scriptorium/plan"
    else:
      echo "scriptorium: spec.md unchanged"

proc cmdAsk() =
  ## Start a read-only Q&A session with the Architect.
  runInteractiveAskSession(getCurrentDir())

proc cmdWorktrees() =
  ## List active git worktrees and which tickets they belong to.
  let worktrees = listActiveTicketWorktrees(getCurrentDir())
  if worktrees.len == 0:
    echo "scriptorium: no active ticket worktrees"
  else:
    echo WorktreesHeader
    for item in worktrees:
      echo item.worktree & "\t" & item.ticketId & "\t" & item.branch

when isMainModule:
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
  of "worktrees":
    cmdWorktrees()
  of "--init":
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
