# FlowSpace Bot Architecture

## Overview

Bots are automated participants in FlowSpace workspaces. Like Telegram/Slack/Discord bots, they connect via API keys, respond to commands, listen to events, and interact with channels programmatically.

## Platform Research Synthesis

### Telegram Bots
- API key auth via HTTP token in URL or header
- Dual mode: webhook (push) or long-polling (getUpdates)
- Commands via `/command` prefix, parsed server-side
- BotFather for bot creation/management
- Inline queries for context-free interaction

### Slack Bots  
- OAuth2 bot tokens with granular scopes
- Events API (webhook) + Socket Mode (WebSocket)
- Slash commands registered via API
- Block Kit for rich UI messages
- App manifest for declarative config

### Discord Bots
- Gateway-based WebSocket connection with intents
- Slash commands via REST API registration
- Interaction webhook for command handling
- Bot token in `Authorization: Bot <token>` header
- Application commands scoped to guild (server)

### FlowSpace Adaptation
Bots follow the **Telegram model** for simplicity with **Discord-style** WebSocket gateway:
- API key auth (not OAuth — simpler for self-hosted)
- WebSocket-based runtime (primary) + webhook fallback (optional)
- Slash commands registered via API
- Bot management UI in admin panel (like BotFather, but in-app)

## Database Schema

### New Prisma Models

```prisma
model Bot {
  id          String       @id @default(uuid())
  workspaceId String
  name        String       // unique identifier per workspace (e.g. "pollbot")
  displayName String       // human-readable name
  description String?
  avatarUrl   String?
  createdBy   String       // user who created the bot
  status      BotStatus    @default(ACTIVE)
  createdAt   DateTime     @default(now())
  updatedAt   DateTime     @updatedAt
  
  workspace   Workspace    @relation(fields: [workspaceId], references: [id], onDelete: Cascade)
  apiKeys     BotApiKey[]
  commands    BotCommand[]
  events      BotEventSubscription[]
  
  @@unique([workspaceId, name])
  @@index([workspaceId])
  @@index([workspaceId, status])
}

model BotApiKey {
  id        String    @id @default(uuid())
  botId     String
  keyHash   String    // bcrypt hash of the API key
  prefix    String    // first 8 chars for display (e.g. "flobot_xxxx...")
  lastUsed  DateTime?
  expiresAt DateTime? // optional expiry
  createdAt DateTime  @default(now())
  
  bot       Bot       @relation(fields: [botId], references: [id], onDelete: Cascade)
  
  @@index([botId])
  @@index([keyHash])
}

model BotCommand {
  id          String           @id @default(uuid())
  botId       String
  command     String           // e.g. "/help", "/poll create"
  description String           // e.g. "Display help information"
  handlerType BotHandlerType   @default(WEBSOCKET)
  handlerUrl  String?          // webhook URL (only for WEBHOOK type)
  enabled     Boolean          @default(true)
  createdAt   DateTime         @default(now())
  updatedAt   DateTime         @updatedAt
  
  bot         Bot              @relation(fields: [botId], references: [id], onDelete: Cascade)
  
  @@unique([botId, command])
  @@index([botId])
}

model BotEventSubscription {
  id        String   @id @default(uuid())
  botId     String
  event     String   // e.g. "message.new", "channel.created", "user.joined"
  enabled   Boolean  @default(true)
  createdAt DateTime @default(now())
  
  bot       Bot      @relation(fields: [botId], references: [id], onDelete: Cascade)
  
  @@unique([botId, event])
  @@index([botId])
}

model BotMessage {
  id          String    @id @default(uuid())
  botId       String
  channelId   String
  content     String
  attachments String[]  @default([])
  parentId    String?
  createdAt   DateTime  @default(now())
  
  bot         Bot       @relation(fields: [botId], references: [id], onDelete: Cascade)
  channel     Channel   @relation(fields: [channelId], references: [id], onDelete: Cascade)
  parent      ChatMessage? @relation("BotMessageThread", fields: [parentId], references: [id])
  
  @@index([botId, createdAt])
  @@index([channelId, createdAt])
}

enum BotStatus {
  ACTIVE
  DISABLED
}

enum BotHandlerType {
  WEBSOCKET
  WEBHOOK
  INLINE
}
```

## Backend Architecture

### New Module: `bots/`

```
bots/
  bots.module.ts           # Module definition
  bots.service.ts          # Bot CRUD, key management
  bots.controller.ts       # REST endpoints (admin only)
  bots.gateway.ts          # WebSocket gateway for bot runtime
  bots-auth.guard.ts       # API key auth guard
  bots-command.service.ts  # Command parsing + routing
  bots-event.service.ts    # Event subscription + dispatch
  dto/
    create-bot.dto.ts
    update-bot.dto.ts
    create-command.dto.ts
```

### REST API Endpoints

All prefixed with `/api/v1`:

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | `/workspaces/:wid/bots` | JWT Admin | Create bot |
| GET | `/workspaces/:wid/bots` | JWT Member | List workspace bots |
| GET | `/workspaces/:wid/bots/:bid` | JWT Member | Get bot details |
| PATCH | `/workspaces/:wid/bots/:bid` | JWT Admin | Update bot |
| DELETE | `/workspaces/:wid/bots/:bid` | JWT Admin | Delete bot |
| POST | `/workspaces/:wid/bots/:bid/keys` | JWT Admin | Generate API key (returns full key once) |
| GET | `/workspaces/:wid/bots/:bid/keys` | JWT Admin | List key prefixes (no secrets) |
| DELETE | `/workspaces/:wid/bots/:bid/keys/:kid` | JWT Admin | Revoke API key |
| POST | `/workspaces/:wid/bots/:bid/commands` | JWT Admin | Register command |
| GET | `/workspaces/:wid/bots/:bid/commands` | JWT Admin | List commands |
| PATCH | `/workspaces/:wid/bots/:bid/commands/:cid` | JWT Admin | Toggle/update command |
| DELETE | `/workspaces/:wid/bots/:bid/commands/:cid` | JWT Admin | Remove command |
| POST | `/workspaces/:wid/bots/:bid/events` | JWT Admin | Subscribe to event |
| GET | `/workspaces/:wid/bots/:bid/events` | JWT Admin | List subscriptions |
| DELETE | `/workspaces/:wid/bots/:bid/events/:eid` | JWT Admin | Unsubscribe |

### Bot Authentication

Bots authenticate via API key in two ways:

1. **WebSocket**: `auth: { token: "flobot_xxxx..." }` in handshake
2. **HTTP**: `Authorization: Bot flobot_xxxx...` header

`BotAuthGuard` validates:
- Extract key from header/handshake
- Look up bot by key prefix
- bcrypt compare against stored hash
- Check bot status (ACTIVE) and key expiry
- Set `request.bot` = { id, workspaceId, name }

### Command Handling

When a user sends a message starting with `/`, the chat gateway:
1. Checks if the first word matches any registered bot command in the workspace
2. If matched, routes to the bot's handler:
   - **WebSocket**: emits `command.invoked` event to the bot's connected socket
   - **Webhook**: POST to `handlerUrl` with `{ command, args, channelId, userId, messageId }`
   - **Inline**: returns response inline via REST

### Bot WebSocket Protocol

Bots connect to the same WebSocket gateway as users:

**Connection**:
```
socket.io?workspaceId=xxx
auth: { token: "flobot_xxxx..." }
```

**Events bot receives**:
- `command.invoked` - { command, args, channelId, userId, messageId, timestamp }
- `message.new` - { ...message } (if subscribed)
- `user.joined` - { userId, userName } (if subscribed)
- `channel.created` - { channel } (if subscribed)

**Events bot sends**:
- `message.send` - { channelId, content, attachments?, threadId? }
- `reaction.add` - { channelId, messageId, emoji }

## Bot SDK Design

### Package: `@flowspace/bot-sdk`

```typescript
import { Bot } from '@flowspace/bot-sdk';

const bot = new Bot({
  apiKey: 'flobot_xxxxxxxxxxxx',
  workspaceId: 'ws-uuid',
  serverUrl: 'https://flowspace.company.com',
});

// Register commands
bot.command('/help', async (ctx) => {
  await ctx.reply('Available commands: /help, /poll');
});

bot.command('/poll create', async (ctx) => {
  // ctx.args = everything after "/poll create"
  await ctx.reply(`Poll created: ${ctx.args}`);
});

// Listen to events
bot.on('message.new', async (msg) => {
  if (msg.content.includes('hello')) {
    await bot.sendMessage(msg.channelId, 'Hello back! 👋');
  }
});

bot.on('user.joined', async (user) => {
  await bot.sendMessage('general', `Welcome ${user.userName}! 🎉`);
});

// Connect
await bot.connect();
```

### SDK Internals
- Wraps Socket.IO client with reconnection
- Automatic command registration via REST API on `bot.command()`
- Event filtering based on subscriptions
- Type-safe context objects

## Flutter Client Changes

### Bot Management UI (Admin Panel)

**Location**: Workspace Settings → Bots tab

**Views**:
1. **Bot list**: Cards showing bot name, description, status badge, active command count
2. **Create bot**: Dialog with name (slug auto-generated), display name, description
3. **Bot detail page**: 
   - General settings (name, display name, description, avatar)
   - API keys section (generate new, list prefixes, revoke)
   - Commands section (list, add, toggle, remove)
   - Event subscriptions section (toggle on/off for available events)
   - Danger zone (disable/delete bot)

### Service: `services/bot_service.dart`
- `listBots(workspaceId)` → List<Bot>
- `createBot(workspaceId, data)` → Bot
- `updateBot(workspaceId, botId, data)` → Bot
- `deleteBot(workspaceId, botId)` → void
- `generateApiKey(workspaceId, botId)` → { key, prefix }
- `revokeApiKey(workspaceId, botId, keyId)` → void
- `registerCommand(workspaceId, botId, data)` → BotCommand
- `subscribeEvent(workspaceId, botId, event)` → BotEventSubscription

## Roadmap Integration

Bot infrastructure completes these roadmap systems:

| System | Bot Impact |
|--------|------------|
| **Admin** (Red→Green) | Bot management UI = key admin feature |
| **Streams** (Yellow→Green) | Bot messages + commands enrich chat |
| **Realtime** (Yellow→Green) | Bot WebSocket = validates realtime infra |
| **Notifications** (Yellow→Green) | Bots can trigger notifications |

## Security Considerations

- API keys are bcrypt-hashed; plaintext shown only once at creation
- Bots can only operate in their own workspace (enforced by BotAuthGuard)
- Bot messages are tagged with `botId` for audit trail
- Rate limiting per-bot (future: configurable in bot settings)
- Bots cannot perform admin actions (create channels, manage members)
- Bot API keys never grant user-level JWT access
