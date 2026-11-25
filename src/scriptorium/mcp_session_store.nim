import
  std/[locks, options]

type
  McpSessionExpiredError* = object of ValueError

  McpSessionRecord* = object
    descriptor*: string
    completion*: string
    methods*: string
    initialized*: bool

  SharedBytes = object
    data: pointer
    length: int

  SharedSession = object
    token: SharedBytes
    descriptor: SharedBytes
    completion: SharedBytes
    methods: SharedBytes
    initialized: bool
    next: ptr SharedSession

var
  registryLock: Lock
  firstSession: ptr SharedSession

proc sharedCopy(value: string): SharedBytes =
  ## Copy bytes into explicitly owned shared storage, with no traced Nim references.
  result.length = value.len
  if value.len > 0:
    result.data = allocShared(value.len)
    copyMem(result.data, unsafeAddr value[0], value.len)

proc localCopy(value: SharedBytes): string =
  ## Copy shared bytes into the requesting thread's own string before releasing the registry lock.
  result = newString(value.length)
  if value.length > 0: copyMem(addr result[0], value.data, value.length)

proc release(value: SharedBytes) =
  ## Release one raw shared allocation without invoking another thread's reference counters.
  if value.data != nil: deallocShared(value.data)

proc matches(value: SharedBytes, token: string): bool =
  ## Compare a scoped token while the registry lock protects its raw bytes.
  value.length == token.len and (token.len == 0 or equalMem(value.data, unsafeAddr token[0], token.len))

proc find(token: string): ptr SharedSession =
  ## Find one live record while the calling operation holds the registry lock.
  result = firstSession
  while result != nil and not result.token.matches(token): result = result.next

proc snapshot(node: ptr SharedSession): McpSessionRecord =
  ## Materialize only thread-local strings while a live record is locked.
  McpSessionRecord(descriptor: localCopy(node.descriptor), completion: localCopy(node.completion),
    methods: localCopy(node.methods), initialized: node.initialized)

proc createMcpRecord*(token: string, record: McpSessionRecord) =
  ## Register a session using raw shared bytes; servers, closures and JSON nodes never cross threads.
  withLock registryLock:
    if find(token) != nil: raise newException(ValueError, "Duplicate scoped MCP session")
    let node = createShared(SharedSession)
    node.token = sharedCopy(token)
    node.descriptor = sharedCopy(record.descriptor)
    node.completion = sharedCopy(record.completion)
    node.methods = sharedCopy(record.methods)
    node.initialized = record.initialized
    node.next = firstSession
    firstSession = node

proc readMcpRecord*(token: string): Option[McpSessionRecord] =
  ## Return an owned local snapshot or none after expiration.
  withLock registryLock:
    let node = find(token)
    if node != nil: result = some(snapshot(node))

proc updateMcpRecord*(token: string, operation: proc(record: var McpSessionRecord) {.gcsafe.}) =
  ## Serialize a record update and retain the original bytes if its operation fails.
  withLock registryLock:
    let node = find(token)
    if node == nil: raise newException(McpSessionExpiredError, "Scoped MCP session expired")
    var record = snapshot(node)
    operation(record)
    let
      descriptor = sharedCopy(record.descriptor)
      completion = sharedCopy(record.completion)
      methods = sharedCopy(record.methods)
    release(node.descriptor)
    release(node.completion)
    release(node.methods)
    node.descriptor = descriptor
    node.completion = completion
    node.methods = methods
    node.initialized = record.initialized

proc expireMcpRecord*(token: string): Option[McpSessionRecord] =
  ## Expire a token atomically, return its final local snapshot and release every shared allocation.
  withLock registryLock:
    var previous: ptr SharedSession
    var node = firstSession
    while node != nil:
      if node.token.matches(token):
        result = some(snapshot(node))
        if previous == nil: firstSession = node.next
        else: previous.next = node.next
        release(node.token)
        release(node.descriptor)
        release(node.completion)
        release(node.methods)
        deallocShared(node)
        return
      previous = node
      node = node.next

proc markMcpInitialized*(token: string) =
  ## Preserve successful initialization only while its token is still live.
  withLock registryLock:
    let node = find(token)
    if node != nil: node.initialized = true

initLock(registryLock)
