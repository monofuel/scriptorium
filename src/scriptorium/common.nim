## Shared types and utilities for the scriptorium orchestrator.

type
  ProcessStartedHandler* = proc(pid: int)
  CancellationCheck* = proc(): bool

  ContinuationPromptBuilder* = proc(workingDir: string): string
    ## Called before each retry attempt to build dynamic continuation text.
    ## Receives the agent working directory and returns the continuation text.
