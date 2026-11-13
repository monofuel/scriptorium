import
  std/atomics

var outputBytes: Atomic[int]

proc recordOutputBytes*(bytes: int) =
  ## Count new transcript bytes across all concurrent agent roles.
  if bytes < 0: raise newException(ValueError, "Output bytes cannot be negative")
  discard outputBytes.fetchAdd(bytes)

proc getSessionOutputBytes*(): int =
  ## Read cumulative output without depending on ticket lifetimes.
  outputBytes.load()

proc resetOutputUsage*() =
  ## Start a new accounting interval before launching agent threads.
  outputBytes.store(0)
