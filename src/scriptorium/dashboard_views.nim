import
  std/[options, sequtils, strformat, strutils, xmltree]

const
  # TODO: vendor these locally so the dashboard works without internet access.
  HtmxCdn = "https://unpkg.com/htmx.org@2.0.4"
  HtmxWsExt = "https://unpkg.com/htmx-ext-ws@2.0.3/ws.js"

  NavItems = [
    ("Overview", "/", "overview"),
    ("Ticket Board", "/tickets", "tickets"),
    ("Merge Queue", "/queue", "queue"),
    ("Agents", "/agents", "agents"),
    ("Spec", "/spec", "spec"),
    ("Logs", "/logs", "logs"),
  ]

  DashboardCss = """
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body { font-family: monospace; background: #0d1117; color: #c9d1d9; }
    nav { display: flex; gap: 0; background: #161b22; border-bottom: 1px solid #30363d; padding: 0 16px; }
    nav a { padding: 12px 16px; color: #8b949e; text-decoration: none; border-bottom: 2px solid transparent; }
    nav a:hover { color: #c9d1d9; }
    nav a.active { color: #58a6ff; border-bottom-color: #58a6ff; }
    .container { max-width: 1200px; margin: 0 auto; padding: 24px; }
    h1 { font-size: 1.4em; margin-bottom: 16px; color: #e6edf3; }
    .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(280px, 1fr)); gap: 16px; }
    .card { background: #161b22; border: 1px solid #30363d; border-radius: 6px; padding: 16px; }
    .card h2 { font-size: 1em; color: #8b949e; margin-bottom: 12px; text-transform: uppercase; letter-spacing: 0.05em; }
    .card .value { font-size: 1.6em; color: #e6edf3; }
    .card .detail { color: #8b949e; font-size: 0.85em; margin-top: 4px; }
    .status-ok { color: #3fb950; }
    .status-warn { color: #d29922; }
    .status-error { color: #f85149; }
    .badge { display: inline-block; padding: 2px 8px; border-radius: 12px; font-size: 0.8em; }
    .badge-green { background: #1b4332; color: #3fb950; }
    .badge-yellow { background: #3d2e00; color: #d29922; }
    .badge-red { background: #3d0000; color: #f85149; }
    .badge-blue { background: #0c2d6b; color: #58a6ff; }
    .loading { color: #8b949e; font-style: italic; }
    .kanban { display: flex; gap: 16px; }
    .kanban-column { flex: 1; min-width: 0; }
    .kanban-column h2 { font-size: 1em; color: #8b949e; margin-bottom: 12px; text-transform: uppercase; letter-spacing: 0.05em; }
    .ticket-card { background: #161b22; border: 1px solid #30363d; border-radius: 6px; padding: 12px; margin-bottom: 8px; cursor: pointer; }
    .ticket-card:hover { border-color: #58a6ff; }
    .ticket-card .ticket-id { color: #8b949e; font-size: 0.85em; }
    .ticket-card .ticket-title { color: #e6edf3; margin-top: 4px; }
    .ticket-card .ticket-meta { color: #8b949e; font-size: 0.8em; margin-top: 4px; }
    .ticket-detail { background: #0d1117; border: 1px solid #30363d; border-radius: 4px; padding: 12px; margin-top: 8px; white-space: pre-wrap; font-size: 0.85em; }
    .queue-list { list-style: decimal; padding-left: 24px; }
    .queue-list li { background: #161b22; border: 1px solid #30363d; border-radius: 6px; padding: 12px; margin-bottom: 8px; }
    .queue-list li.active { background: #0c2d6b; border-color: #58a6ff; }
    .queue-item-id { color: #8b949e; font-size: 0.85em; }
    .queue-item-summary { color: #e6edf3; margin-top: 4px; }
    .queue-item-branch { color: #8b949e; font-size: 0.8em; margin-top: 2px; }
    .history-list { margin-top: 16px; }
    .history-item { padding: 6px 0; border-bottom: 1px solid #30363d; font-size: 0.9em; }
    .history-pass { color: #3fb950; }
    .history-fail { color: #f85149; }
    .agents-table { width: 100%; border-collapse: collapse; }
    .agents-table th { text-align: left; color: #8b949e; padding: 8px 12px; border-bottom: 2px solid #30363d; text-transform: uppercase; font-size: 0.85em; letter-spacing: 0.05em; }
    .agents-table td { padding: 8px 12px; border-bottom: 1px solid #30363d; color: #c9d1d9; }
    .agents-table tfoot td { color: #8b949e; padding-top: 12px; border-bottom: none; }
    .spec-content { background: #161b22; border: 1px solid #30363d; border-radius: 6px; padding: 16px; white-space: pre-wrap; font-size: 0.9em; max-height: 80vh; overflow-y: scroll; }
    .log-controls { display: flex; gap: 12px; margin-bottom: 16px; }
    .log-controls select { background: #161b22; color: #c9d1d9; border: 1px solid #30363d; border-radius: 4px; padding: 8px 12px; font-family: monospace; }
    .log-content { background: #161b22; border: 1px solid #30363d; border-radius: 6px; padding: 16px; white-space: pre-wrap; font-size: 0.85em; max-height: 70vh; overflow-y: scroll; }
  """

proc renderNavigation*(activeView: string): string =
  ## Render the navigation bar with the given view marked as active.
  result = "<nav>"
  for (label, href, id) in NavItems:
    let cls = if id == activeView: " class=\"active\"" else: ""
    result.add(&"""<a href="{href}"{cls}>{label}</a>""")
  result.add("</nav>")

proc renderStatusFragment*(pidAlive: bool, uptime: Option[string], paused: bool,
                           loopIteration: int): string =
  ## Render the orchestrator status card content as an HTML fragment.
  let stateClass = if pidAlive: "status-ok" else: "status-error"
  let stateLabel = if pidAlive: "Running" else: "Stopped"
  let uptimeStr = if uptime.isSome: uptime.get else: "-"
  let pausedHtml = if paused: """ <span class="badge badge-yellow">PAUSED</span>""" else: ""
  let iterStr = $loopIteration
  result = &"""<h2>Orchestrator Status</h2>""" &
    &"""<div class="value"><span class="{stateClass}">{stateLabel}</span>{pausedHtml}</div>""" &
    &"""<div class="detail">Uptime: {uptimeStr} | Iteration: {iterStr}</div>"""

proc renderTicketsFragment*(openCount: int, inProgressCount: int,
                            doneCount: int): string =
  ## Render ticket counts as an HTML fragment.
  let openStr = $openCount
  let progressStr = $inProgressCount
  let doneStr = $doneCount
  result = """<h2>Tickets</h2>""" &
    &"""<div class="value">{progressStr} <span class="detail">in progress</span></div>""" &
    &"""<div class="detail"><span class="badge badge-blue">{openStr} open</span> """ &
    &"""<span class="badge badge-green">{doneStr} done</span></div>"""

proc renderAgentsFragment*(activeCount: int, maxAgents: int): string =
  ## Render active agents summary as an HTML fragment.
  let activeStr = $activeCount
  let maxStr = $maxAgents
  result = """<h2>Active Agents</h2>""" &
    &"""<div class="value">{activeStr} / {maxStr}</div>""" &
    &"""<div class="detail">agent slots in use</div>"""

proc renderQueueFragment*(pendingCount: int, hasActive: bool): string =
  ## Render merge queue depth as an HTML fragment.
  let activeLabel = if hasActive: "1 active" else: "idle"
  let pendingStr = $pendingCount
  result = """<h2>Merge Queue</h2>""" &
    &"""<div class="value">{pendingStr} pending</div>""" &
    &"""<div class="detail">{activeLabel}</div>"""

proc renderHealthFragment*(healthy: bool, hasData: bool,
                           lastCommit: Option[string]): string =
  ## Render health status as an HTML fragment.
  if not hasData:
    result = """<h2>Health</h2><div class="value loading">No data</div>"""
    return
  let cls = if healthy: "status-ok" else: "status-error"
  let label = if healthy: "Healthy" else: "Unhealthy"
  var commitStr = ""
  if lastCommit.isSome:
    let fullCommit = lastCommit.get
    let shortCommit = if fullCommit.len > 7: fullCommit[0..6] else: fullCommit
    commitStr = &""" <span class="detail">({shortCommit})</span>"""
  result = &"""<h2>Health</h2><div class="value"><span class="{cls}">{label}</span>{commitStr}</div>"""

proc renderOverviewSection*(): string =
  ## Render the overview section with htmx-powered cards for each data section.
  result = """<div class="container"><h1>Overview</h1><div class="grid">""" &
    """<div class="card" id="overview-status" hx-get="/fragments/status" hx-trigger="load"><span class="loading">Loading status...</span></div>""" &
    """<div class="card" id="overview-tickets" hx-get="/fragments/tickets" hx-trigger="load"><span class="loading">Loading tickets...</span></div>""" &
    """<div class="card" id="overview-agents" hx-get="/fragments/agents" hx-trigger="load"><span class="loading">Loading agents...</span></div>""" &
    """<div class="card" id="overview-queue" hx-get="/fragments/queue" hx-trigger="load"><span class="loading">Loading queue...</span></div>""" &
    """<div class="card" id="overview-health" hx-get="/fragments/health" hx-trigger="load"><span class="loading">Loading health...</span></div>""" &
    """</div></div>"""

proc renderPage*(activeView: string, bodyContent: string): string =
  ## Render a full HTML page with head, navigation, and body content.
  let nav = renderNavigation(activeView)
  result = "<!DOCTYPE html><html><head>" &
    """<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">""" &
    "<title>scriptorium dashboard</title>" &
    "<style>" & DashboardCss & "</style>" &
    &"""<script src="{HtmxCdn}"></script>""" &
    &"""<script src="{HtmxWsExt}"></script>""" &
    "</head>" &
    """<body hx-ext="ws" ws-connect="/ws">""" &
    nav & bodyContent &
    "</body></html>"

proc renderOverviewPage*(): string =
  ## Render the full overview page with navigation and overview section.
  let overview = renderOverviewSection()
  result = renderPage("overview", overview)

type
  TicketCard* = object
    id*: string
    area*: string
    title*: string
    state*: string
    elapsed*: string
    attempt*: string
    outcome*: string
    wallTime*: string

proc parseTicketCard*(id: string, area: string, title: string, state: string,
                      content: string): TicketCard =
  ## Build a ticket card from ticket fields and raw markdown content.
  result = TicketCard(id: id, area: area, title: title, state: state)
  var inMetrics = false
  for line in content.splitLines():
    let trimmed = line.strip()
    if trimmed == "## Metrics":
      inMetrics = true
      continue
    if inMetrics and trimmed.startsWith("## "):
      break
    if inMetrics:
      if trimmed.startsWith("- attempt_count: "):
        result.attempt = trimmed["- attempt_count: ".len..^1].strip()
      elif trimmed.startsWith("- wall_time_seconds: "):
        let secs = trimmed["- wall_time_seconds: ".len..^1].strip()
        result.wallTime = secs & "s"
      elif trimmed.startsWith("- outcome: "):
        result.outcome = trimmed["- outcome: ".len..^1].strip()

proc renderTicketCard*(card: TicketCard): string =
  ## Render one ticket card as an HTML div with htmx click-to-expand.
  let areaBadge = if card.area.len > 0:
    let a = card.area
    &""" <span class="badge badge-blue">{a}</span>"""
  else:
    ""
  let ticketId = card.id
  let title = card.title
  var meta = ""
  if card.state == "in-progress":
    if card.elapsed.len > 0:
      meta.add(&"""<span>Elapsed: {card.elapsed}</span>""")
    if card.attempt.len > 0:
      if meta.len > 0: meta.add(" | ")
      meta.add(&"""<span>Attempt: {card.attempt}</span>""")
  elif card.state == "done":
    if card.outcome.len > 0:
      meta.add(&"""<span>Outcome: {card.outcome}</span>""")
    if card.wallTime.len > 0:
      if meta.len > 0: meta.add(" | ")
      meta.add(&"""<span>Wall: {card.wallTime}</span>""")
  let metaHtml = if meta.len > 0:
    &"""<div class="ticket-meta">{meta}</div>"""
  else:
    ""
  result = &"""<div class="ticket-card" hx-get="/api/tickets/{ticketId}" hx-trigger="click" hx-target="find .ticket-detail" hx-swap="innerHTML">""" &
    &"""<span class="ticket-id">{ticketId}</span>{areaBadge}""" &
    &"""<div class="ticket-title">{title}</div>""" &
    metaHtml &
    """<div class="ticket-detail"></div></div>"""

proc renderTicketBoardSection*(openCards: seq[TicketCard],
                               inProgressCards: seq[TicketCard],
                               doneCards: seq[TicketCard]): string =
  ## Render the three-column kanban board section.
  result = """<div class="container"><h1>Ticket Board</h1><div class="kanban">"""
  result.add("""<div class="kanban-column"><h2>Open</h2>""")
  for card in openCards:
    result.add(renderTicketCard(card))
  result.add("</div>")
  result.add("""<div class="kanban-column"><h2>In Progress</h2>""")
  for card in inProgressCards:
    result.add(renderTicketCard(card))
  result.add("</div>")
  result.add("""<div class="kanban-column"><h2>Done</h2>""")
  for card in doneCards:
    result.add(renderTicketCard(card))
  result.add("</div>")
  result.add("</div></div>")

type
  QueueViewItem* = object
    ticketId*: string
    branch*: string
    summary*: string
    isActive*: bool

  MergeHistoryItem* = object
    ticketId*: string
    passed*: bool
    summary*: string

  AgentViewSlot* = object
    role*: string
    ticketId*: string
    areaId*: string
    elapsed*: string
    status*: string

proc renderQueueItem*(item: QueueViewItem): string =
  ## Render a single merge queue item as an HTML list item.
  let cls = if item.isActive: """ class="active"""" else: ""
  let ticketId = item.ticketId
  let summary = item.summary
  let branch = item.branch
  result = &"""<li{cls}><span class="queue-item-id">{ticketId}</span>""" &
    &"""<div class="queue-item-summary">{summary}</div>""" &
    &"""<div class="queue-item-branch">{branch}</div></li>"""

proc renderMergeHistoryItem*(item: MergeHistoryItem): string =
  ## Render a single merge history entry with pass/fail indicator.
  let indicator = if item.passed: """<span class="history-pass">&#10003;</span>"""
                  else: """<span class="history-fail">&#10007;</span>"""
  let ticketId = item.ticketId
  let summary = item.summary
  result = &"""<div class="history-item">{indicator} <strong>{ticketId}</strong> {summary}</div>"""

proc renderMergeQueueSection*(pending: seq[QueueViewItem],
                              history: seq[MergeHistoryItem]): string =
  ## Render the merge queue section with pending items list and recent history.
  result = """<div class="container"><h1>Merge Queue</h1>"""
  result.add("""<div id="queue-content" hx-get="/api/queue" hx-trigger="load">""")
  if pending.len == 0:
    result.add("""<p class="detail">No pending items.</p>""")
  else:
    result.add("""<ol class="queue-list">""")
    for item in pending:
      result.add(renderQueueItem(item))
    result.add("</ol>")
  if history.len > 0:
    result.add("""<h2 style="margin-top: 24px; color: #8b949e; text-transform: uppercase; letter-spacing: 0.05em; font-size: 1em;">Recent History</h2>""")
    result.add("""<div class="history-list">""")
    for item in history:
      result.add(renderMergeHistoryItem(item))
    result.add("</div>")
  result.add("</div></div>")

proc renderMergeQueuePage*(pending: seq[QueueViewItem],
                           history: seq[MergeHistoryItem]): string =
  ## Render the full merge queue page with navigation.
  let section = renderMergeQueueSection(pending, history)
  result = renderPage("queue", section)

proc renderAgentRow*(slot: AgentViewSlot): string =
  ## Render a single agent slot as a table row.
  let role = slot.role
  let identifier = if slot.ticketId.len > 0: slot.ticketId
                   elif slot.areaId.len > 0: slot.areaId
                   else: "-"
  let elapsed = if slot.elapsed.len > 0: slot.elapsed else: "-"
  let status = slot.status
  result = &"<tr><td>{role}</td><td>{identifier}</td><td>{elapsed}</td><td>{status}</td></tr>"

proc renderAgentsSection*(agents: seq[AgentViewSlot], maxAgents: int): string =
  ## Render the agents section with a table of active slots and capacity footer.
  let usedCount = agents.len
  let usedStr = $usedCount
  let maxStr = $maxAgents
  result = """<div class="container"><h1>Agents</h1>"""
  result.add("""<div id="agents-content" hx-get="/api/agents" hx-trigger="load">""")
  result.add("""<table class="agents-table"><thead><tr>""")
  result.add("<th>Role</th><th>Ticket/Area</th><th>Elapsed</th><th>Status</th>")
  result.add("</tr></thead><tbody>")
  if agents.len == 0:
    result.add("""<tr><td colspan="4" class="detail">No active agents.</td></tr>""")
  else:
    for slot in agents:
      result.add(renderAgentRow(slot))
  result.add("</tbody>")
  result.add(&"""<tfoot><tr><td colspan="4">{usedStr}/{maxStr} slots in use</td></tr></tfoot>""")
  result.add("</table></div></div>")

proc renderAgentsPage*(agents: seq[AgentViewSlot], maxAgents: int): string =
  ## Render the full agents page with navigation.
  let section = renderAgentsSection(agents, maxAgents)
  result = renderPage("agents", section)

proc escapeHtml*(text: string): string =
  ## Escape HTML special characters to prevent XSS when rendering raw text.
  result = xmltree.escape(text)

proc renderSpecSection*(): string =
  ## Render the spec section with an htmx-loaded preformatted block.
  result = """<div class="container"><h1>Spec</h1>""" &
    """<pre class="spec-content" id="spec-content" hx-get="/fragments/spec" hx-trigger="load">""" &
    """<span class="loading">Loading spec...</span></pre></div>"""

proc renderSpecPage*(): string =
  ## Render the full spec page with navigation.
  let section = renderSpecSection()
  result = renderPage("spec", section)

proc renderLogsSection*(): string =
  ## Render the logs section with role and ID dropdowns and a content area.
  result = """<div class="container"><h1>Logs</h1>""" &
    """<div class="log-controls">""" &
    """<select id="log-role" name="role" hx-get="/api/log-ids" hx-target="#log-id" hx-trigger="change" hx-include="this">""" &
    """<option value="">Select role...</option>""" &
    """<option value="coder">coder</option>""" &
    """<option value="manager">manager</option>""" &
    """<option value="review">review</option>""" &
    """<option value="architect">architect</option>""" &
    """<option value="audit">audit</option>""" &
    """</select>""" &
    """<select id="log-id" name="id" hx-get="/api/log-content" hx-target="#log-content" hx-trigger="change" hx-include="[name='role'],[name='id']">""" &
    """<option value="">Select ID...</option>""" &
    """</select>""" &
    """</div>""" &
    """<pre class="log-content" id="log-content">Select a role and identifier to view logs.</pre>""" &
    """</div>"""

proc renderLogsPage*(): string =
  ## Render the full logs page with navigation.
  let section = renderLogsSection()
  result = renderPage("logs", section)

proc renderLogIdOptions*(ids: seq[string]): string =
  ## Render HTML option elements for a list of log identifiers.
  result = """<option value="">Select ID...</option>"""
  for id in ids:
    let escaped = escapeHtml(id)
    result.add(&"""<option value="{escaped}">{escaped}</option>""")
