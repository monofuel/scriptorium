import
  std/[os, strformat, strutils],
  guildy,
  ./config

proc runDiscordBot*(repoPath: string) =
  ## Start the Discord bot gateway connection.
  let token = getEnv("DISCORD_TOKEN")
  if token.len == 0:
    echo "scriptorium: DISCORD_TOKEN environment variable is required"
    quit(1)

  let cfg = loadConfig(repoPath)
  let channelId = cfg.discord.channelId
  if channelId.len == 0:
    echo "scriptorium: discord.channelId is required in scriptorium.json"
    quit(1)

  let allowedUsers = cfg.discord.allowedUsers
  let bot = newDiscordBot(token)

  bot.onMessage = proc(msg: DiscordMessage) {.gcsafe.} =
    if msg.channelId != channelId:
      return
    if msg.author.bot:
      return
    if allowedUsers.len > 0 and msg.author.id notin allowedUsers:
      return
    let user = msg.author.username
    let content = msg.content
    echo &"scriptorium: discord message from {user}: {content}"

  echo "scriptorium: starting Discord bot"
  bot.run()
