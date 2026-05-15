# Target
Fix bots.gateway.ts, bots.service.ts — the bot subsystem is non-functional (4 P0 bugs)

# Changes (apply EVERY one):

## bots.gateway.ts

### P0: Fix bot connection rejection (lines ~46-51)
The `getBot(workspaceId, botId, 'system')` call always fails because getBot() calls requireMember().
Fix: Add a new method to BotsService called `getBotForConnection(workspaceId, botId)` that does the Prisma lookup WITHOUT calling requireMember.
Then change the call in handleConnection to use `getBotForConnection` instead.
OR: simpler fix — in handleConnection, directly query prisma for the bot instead of going through getBot at all:
```typescript
const bot = await this.botsService.getBotForConnection(botContext.workspaceId, botContext.botId);
```

### P0: Fix bot message channel name (lines ~117-120)
Change `'message.sent'` to the WorkspaceEvents constant:
Add import: `import { WorkspaceEvents } from '../../libs/shared';`
Then: `await this.redis.publish(WorkspaceEvents.MESSAGE_SENT, { ...`

### P0: Fix command routing dead letter
Add onModuleInit to BotsGateway (implement OnModuleInit):
```typescript
async onModuleInit() {
  await this.redis.subscribe(['command.invoked'], (channel: string, payload: string) => {
    if (channel === 'command.invoked') {
      const data = JSON.parse(payload);
      this.dispatchCommandToBot(data.workspaceId, data.botId, 'command.invoked', data);
    }
  });
}
```

### P1: Fix direct Prisma access (lines ~96-108)
Remove `this.botsService['prisma'].botMessage.create(...)` and replace with a call to a new method on BotsService.
First, add `persistAndBroadcastBotMessage` method to BotsService (see bots.service.ts changes).
Then call it from handleBotMessage.

### P1: Add per-bot rate limiting
Add a simple Map-based rate limiter:
```typescript
private botRateLimit = new Map<string, number>();
private readonly RATE_LIMIT_WINDOW = 1000; // 1 second
private readonly RATE_LIMIT_MAX = 10; // 10 messages per second
```
In handleBotMessage: check rate limit, if exceeded emit 'message.failed' with rate limit error.

### P1: Add channel-to-workspace validation
Before persisting bot message, verify channel belongs to bot's workspace.

## bots.service.ts

### P0: Add getBotForConnection method
```typescript
async getBotForConnection(workspaceId: string, botId: string) {
  return this.prisma.bot.findFirst({
    where: { id: botId, workspaceId },
    include: { commands: true, events: true, apiKeys: { select: { id: true, prefix: true, lastUsed: true, expiresAt: true, createdAt: true } } },
  });
}
```

### P0: Add persistAndBroadcastBotMessage
```typescript
async persistBotMessage(botId: string, channelId: string, content: string, attachments?: string[], parentId?: string) {
  // Validate channel belongs to bot's workspace first
  const bot = await this.prisma.bot.findUnique({ where: { id: botId } });
  if (!bot) throw new NotFoundException('Bot not found');
  
  const channel = await this.prisma.channel.findUnique({ where: { id: channelId } });
  if (!channel || channel.workspaceId !== bot.workspaceId) {
    throw new ForbiddenException('Channel not in bot workspace');
  }
  
  return this.prisma.botMessage.create({
    data: { botId, channelId, content, attachments: attachments || [], parentId: parentId || null },
  });
}
```

### P1: Fix bcrypt rounds in generateApiKey
Change `hash(rawKey, 8)` to `hash(rawKey, 12)`.

### P1: Fix API key prefix matching side channel
In `generateApiKey()`: generate a separate keyId (UUID) and store it alongside the prefix. Add `keyId` to the return.
In `validateApiKey()`: accept keyId in addition to apiKey. Look up by keyId instead of prefix. 
Actually, simpler approach for now: just increase bcrypt rounds and add a comment warning about the side channel. The prefix matching is a pragmatic tradeoff. We'll fix it properly by adding keyId in a follow-up.

### P2: Add audit logging placeholder
Add comment at top of key methods: `// TODO: Emit audit event for bot action` — we'll add audit in a follow-up pass.
