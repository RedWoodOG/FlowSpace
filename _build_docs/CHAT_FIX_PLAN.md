# Target
Fix chat.gateway.ts, chat.service.ts, presence.gateway.ts, event-bus.ts

# Changes (apply EVERY one):

## chat.gateway.ts — P0 FIXES FIRST

### P0: Remove anonymous user bypass (lines ~94-109)
DELETE the entire try/catch block in handleConnection that catches auth errors and assigns anonymous user. Replace with:
```typescript
async handleConnection(client: Socket) {
    const payload = await this.extractUser(client);
    client.data.user = payload;
    console.log(`[ChatGateway] Client connected with JWT: ${payload.email}`);
    
    const workspaceId = client.handshake.query.workspaceId as string | undefined;
    const channelId = client.handshake.query.channelId as string | undefined;
    
    if (!workspaceId) {
      client.disconnect(true);
      return;
    }
    // ... rest stays same
```

### P0: Remove runtime require() calls (lines ~157-168)
- DELETE the `const { BotsGateway } = require('../bots/bots.gateway');` line entirely (dead code, never used)
- Move `require('https')` and `require('url')` to top-level imports: add `import * as https from 'https';` at top of file
- In webhook dispatch, use the top-level imports instead of require()

### P1: Fix bulletin authorization
In handleBulletinCreate, handleBulletinUpdate, handleBulletinDelete, handleBulletinPin, handleBulletinUnpin:
- Validate workspaceId against client's actual membership (client.data.user)
- Don't trust data.workspaceId from message body
- Use: `const workspaceId = client.handshake.query.workspaceId as string` (same pattern as handleMessageSend)
- If workspaceId doesn't match or user isn't a member, emit error and return

### P1: Add message content length limit
In handleMessageSend: before processing, check `data.content.length`. If > 50000, emit 'message.failed' with error and return.

### P1: Fix message.edit and message.delete stubs (lines ~255-270)
Wire them to chatService:
- handleMessageEdit: call `this.chatService.editMessage(data.messageId, user.id, data.content)`, emit success/failure
- handleMessageDelete: call `this.chatService.deleteMessage(data.messageId, user.id)`, emit success/failure

### P2: Fix webhook timeout
Add timeout to https.request: `req.setTimeout(10000, () => { req.destroy(); });`
Add error handling on req: `req.on('error', (e) => { console.error('Webhook error:', e); });`

### P2: Validate reaction emoji
In handleReactionAdd/Remove: check `data.emoji.length <= 32`. If not, emit error and return.

### P1: workspace.activity batching
In onModuleInit MESSAGE_SENT handler: remove the workspace.activity broadcast (lines ~58-60). This is a self-DoS. Replace with a comment: `// workspace.activity event removed — too expensive at scale. Use per-channel events.`

## chat.service.ts

### P0: Transactional message send
Wrap sendMessage in a Prisma transaction:
```typescript
const [message] = await this.prisma.$transaction([
  this.prisma.chatMessage.create({ data: { ... }, include: { sender: true } }),
  this.prisma.channel.update({ where: { id: channelId }, data: { updatedAt: new Date() } }),
]);
```

### P1: Reaction race condition fix
Replace read-modify-write with transactional approach. For addReaction:
```typescript
const updated = await this.prisma.$transaction(async (tx) => {
  const msg = await tx.chatMessage.findUnique({ where: { id: messageId } });
  if (!msg) throw new NotFoundException('Message not found');
  const reactions = (msg.reactions as any[]) || [];
  if (reactions.find((r: any) => r.userId === userId && r.emoji === emoji)) {
    throw new ConflictException('Reaction already exists');
  }
  reactions.push({ emoji, userId, timestamp: new Date().toISOString() });
  return tx.chatMessage.update({ where: { id: messageId }, data: { reactions } });
});
```
Do the same pattern for removeReaction.

### P2: Fix N+1 in listChannels
Instead of include: { messages: { take: 1 } }, use a raw query or accept the N+1 for now and add a TODO comment. Actually, simplest fix: add a TODO comment acknowledging the N+1 and promise future optimization.

### P1: Add message content limit
In sendMessage: add `if (content.length > 50000) throw new BadRequestException('Message too long');`

### P2: Paginate getThreadMessages
Add parameter `limit = 100`. Add `take: limit` to the findMany query.

### P2: Combine membership+message query in pin/unpin
Leave for future optimization — add TODO comment. The fix is non-trivial and the current pattern is correct (just slightly inefficient).

## presence.gateway.ts

### P1: Reduce TTL from 60 to 30
Change `private static readonly TTL_SECONDS = 60` to `30`

### P2: Add debounce to heartbeat
Add a Map to track last heartbeat time per user. If heartbeat is within 15 seconds of last, skip Redis operations. Return early.

## event-bus.ts
No changes needed — the dedup claim in README is false but event-bus.ts itself is fine as a simple EventEmitter. We'll fix the README separately.
