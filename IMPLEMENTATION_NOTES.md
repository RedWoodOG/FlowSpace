# FlowSpace Implementation Notes — Hardening Pass
**Date**: 2026-05-14 to 2026-05-15
**Scope**: Full-stack security and engineering standards hardening

---

## 1. What Happened

A council of 5 specialized subagents audited the entire backend codebase (auth, chat, bots, realtime, data layer) against production-readiness standards for high-reliability domains (defense, finance, healthcare). The audit found **49 issues** (13 critical, 21 high, 15 medium). Then 6 subagents applied fixes across 22 files.

---

## 2. Critical Vulnerabilities Found & Fixed

### 2.1 Anonymous User Bypass (P0)
**File**: `backend/src/chat/chat.gateway.ts`

The WebSocket gateway's `handleConnection` method caught all JWT authentication errors and silently assigned a hardcoded anonymous user:
```typescript
// BEFORE (lines ~97-109):
try {
    const payload = await this.extractUser(client);
    client.data.user = payload;
} catch (error) {
    // Allow connection without JWT for testing
    client.data.user = {
        id: 'anonymous',
        email: 'test@flowspace.local',
        displayName: 'Test User',
    };
}
```

This meant any WebSocket client could connect with a valid `workspaceId` query param and gain full messaging, reaction, pinning, and bulletin capabilities — no credentials needed.

**Fix**: Removed the try/catch entirely. Auth failures now prevent connection.

### 2.2 Prisma `--accept-data-loss` on Every Startup (P0)
**File**: `backend/src/database/prisma.service.ts`

`prisma db push --accept-data-loss` ran on every `onModuleInit()` — every application startup, including production. This would silently drop columns, tables, and reshape the database without warning. There was no environment check or safeguard.

**Fix**: Removed `ensurePrismaClient()`, `runMigrations()`, and the `exec()` import entirely. PrismaService now only calls `$connect()` on init and `$disconnect()` on destroy.

### 2.3 Refresh Tokens Stored in Plaintext (P0)
**File**: `backend/src/auth/services/token.service.ts`

`saveRefreshToken` stored the raw `crypto.randomBytes(40).toString('hex')` value directly in the database. A database breach would expose every refresh token in immediately-usable form.

**Fix**: Tokens are now bcrypt-hashed (12 rounds) before storage. Validation iterates active tokens and compares hashes.

### 2.4 No Rate Limiting Anywhere (P0)
**Files**: `backend/src/auth/auth.controller.ts`, `backend/src/main.ts`, `backend/src/app.module.ts`

Zero rate limiting on login, register, refresh, or verify-email endpoints. Brute-force at line speed. WebSocket events also had no rate limiting.

**Fix**: 
- HTTP: `@nestjs/throttler` with 100 requests per 60-second window globally
- WebSocket bots: Per-bot sliding window rate limiter (10 messages/second)
- Added `helmet` package for security headers

### 2.5 CORS Wildcard with `credentials: true` (P0)
**File**: `backend/src/main.ts`

The origin array contained `process.env.FRONTEND_URL || '*'` with `credentials: true`. Platform wildcards (`https://*.onrender.com`, `https://*.railway.app`) allowed any subdomain on those platforms to make credentialed cross-origin requests.

**Fix**: Removed `*` fallback and platform wildcards. `FRONTEND_URL` is now validated at startup — if unset in production, the server exits with an error. In development, defaults to `http://localhost`.

---

## 3. High-Priority Fixes

### 3.1 bcrypt Rounds: 8 → 12
**Files**: `auth.service.ts`, `token.service.ts`, `bots.service.ts`

All `hash(password, 8)` and `hash(rawKey, 8)` calls changed to `hash(password, 12)`. At 8 rounds a GPU does ~100K hashes/sec; at 12 rounds ~3-5/sec.

### 3.2 JWT Algorithm Pinned to HS256
**Files**: `auth.service.ts`, all JwtModule registrations

All `sign()` and `verify()` calls now explicitly specify `algorithm: 'HS256'` / `algorithms: ['HS256']` to prevent algorithm confusion attacks.

### 3.3 Guards Fail-Closed
**Files**: `jwt.guard.ts`, `bots-auth.guard.ts`

Both guards previously returned `true` for non-HTTP contexts. Now throw `UnauthorizedException` for unknown context types.

### 3.4 Transactional Message Send
**File**: `chat.service.ts`

Message creation and channel `updatedAt` update now wrapped in `prisma.$transaction([...])` to prevent ghost messages (message persisted but channel timestamp stale).

### 3.5 Reaction Race Condition Fixed
**File**: `chat.service.ts`

Read-modify-write cycle on reactions JSON column replaced with `$transaction` using atomic read+write. Prevents concurrent reaction adds from silently overwriting each other.

### 3.6 Redis Error Suppression Removed
**File**: `redis.service.ts`

All silent `catch(() => {})` blocks replaced with proper error logging. Added `isHealthy()` method. Publish failures are logged. Callers now handle Redis unavailability explicitly.

### 3.7 Redis Adapter Fails Hard in Production
**Files**: `redis-io.adapter.ts`, `main.ts`

If `REDIS_URL` is missing in production, the server exits with an error. No silent fallback to in-memory adapter that breaks multi-instance message delivery.

### 3.8 Schema Hardening
**File**: `prisma/schema.prisma`

| Change | Before | After |
|--------|--------|-------|
| Thread cascade delete | `onDelete: Cascade` on parent | `onDelete: SetNull` |
| Message content | unbounded `String` | `@db.VarChar(50000)` |
| Soft-delete index | missing | `@@index([channelId, deleted, createdAt])` |
| Dead table | `PresenceSnapshot` model | Removed (presence is Redis-only) |

---

## 4. Bot Subsystem — 4 Critical Bugs Fixed

The bot subsystem was non-functional. Four independent bugs meant bots could not connect, could not receive commands, and their messages never reached users.

### Bug 1: Bots Always Rejected
**Files**: `bots.gateway.ts`, `bots.service.ts`

`handleConnection` called `getBot(workspaceId, botId, 'system')` to bypass membership, but `getBot()` unconditionally called `requireMember()` which threw `ForbiddenException` for userId `'system'`.

**Fix**: Added `getBotForConnection()` method that skips membership check.

### Bug 2: Command Routing Dead Letter
**Files**: `chat.gateway.ts`, `bots.gateway.ts`

`command.invoked` was published to Redis but no code subscribed to it. `dispatchCommandToBot()` existed but was never called.

**Fix**: Added `OnModuleInit` to `BotsGateway` that subscribes to `command.invoked` and routes to the correct bot.

### Bug 3: Bot Messages Never Delivered
**File**: `bots.gateway.ts`

BotsGateway published to Redis channel `'message.sent'` but ChatGateway subscribed to `WorkspaceEvents.MESSAGE_SENT` which is `'workspace.message.sent'`. Different channel names.

**Fix**: Changed BotsGateway to use `WorkspaceEvents.MESSAGE_SENT` constant.

### Bug 4: Bot SDK sendMessage Hangs Forever
**File**: `bot-sdk/src/bot.ts`

The Promise wrapping `message.send` had no timeout. If server crashed before responding, the Promise hung forever.

**Fix**: Added 15-second timeout with `Promise.race`, proper cleanup, and descriptive error messages.

---

## 5. Infrastructure

### 5.1 New Dependencies
| Package | Purpose |
|---------|---------|
| `helmet` | Security headers (CSP, HSTS, X-Frame-Options, etc.) |
| `@nestjs/throttler` | Rate limiting for HTTP endpoints |

### 5.2 Global Middleware
All applied in `main.ts` bootstrap:
- **Helmet**: Security headers
- **Body limits**: 1MB for JSON and URL-encoded
- **ValidationPipe**: Global with `whitelist: true`, `forbidNonWhitelisted: true`, `transform: true`
- **ThrottlerModule**: 100 requests per 60-second window per client

### 5.3 CORS Configuration
```typescript
// FRONTEND_URL validated at startup
const origin = frontendUrl ? [frontendUrl] : ['http://localhost'];
cors: {
  origin,
  credentials: true,
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'PATCH', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization', 'X-Session-Token'],
}
```

---

## 6. Local Development Setup

### 6.1 Prerequisites
- Node.js 22+ (already installed)
- Docker (already running)

### 6.2 File Locations
| File | Purpose |
|------|---------|
| `/tmp/FlowSpace/docker-compose.yml` | PostgreSQL 16 + Redis 7 containers |
| `/tmp/FlowSpace/backend/.env` | All environment variables |
| `/tmp/FlowSpace/backend/config/projectTemplates.json` | Project template registry |

### 6.3 Startup (One Command)
```bash
cd /tmp/FlowSpace

# Start databases
docker compose up -d

# Start backend (in another terminal or background)
cd backend
npx ts-node -r tsconfig-paths/register src/main.ts
```

The server listens on `http://localhost:4000`. Health check: `GET /api/v1/health`

### 6.4 Default Account
```
Email:    admin@flowspace.local
Password: flowspace123
```

### 6.5 .env Reference
```env
DATABASE_URL="postgresql://flowspace:flowspace@localhost:5432/flowspace"
REDIS_URL="redis://localhost:6379"
JWT_SECRET="dev-secret-change-in-production-abc123xyz"
FRONTEND_URL="http://localhost"
NODE_ENV="development"
PORT=4000
MINIO_ACCESS_KEY=dev
MINIO_SECRET_KEY=devdevdev
MINIO_ENDPOINT=http://localhost:9000
MINIO_BUCKET=flowspace-dev
```

---

## 7. API Endpoints (Full Reference)

### Auth
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | `/api/v1/auth/register` | None | Register new user |
| POST | `/api/v1/auth/login` | None | Login, get JWT |
| POST | `/api/v1/auth/register-with-verification` | None | Register with email verification |
| GET | `/api/v1/auth/verify-email?token=` | None | Verify email token |
| POST | `/api/v1/auth/login-with-remember-me` | None | Login with refresh token |
| POST | `/api/v1/auth/refresh` | None | Refresh access token |
| POST | `/api/v1/auth/logout` | JWT | Logout, revoke refresh token |

### Workspaces
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/api/v1/workspaces` | JWT | List user's workspaces |
| POST | `/api/v1/workspaces` | JWT | Create workspace |
| GET | `/api/v1/workspaces/:wid/channels` | JWT | List channels |
| GET | `/api/v1/workspaces/:wid/members` | JWT | List members |
| POST | `/api/v1/workspaces/:wid/members` | JWT | Add member |
| POST | `/api/v1/workspaces/:wid/members/:uid/remove` | JWT | Remove member |
| POST | `/api/v1/workspaces/:wid/members/:uid/role` | JWT | Change member role |

### Chat
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/api/v1/workspaces/:wid/channels` | JWT | List channels |
| POST | `/api/v1/workspaces/:wid/channels` | JWT | Create channel |
| GET | `/api/v1/workspaces/:wid/channels/:cid/messages` | JWT | Get messages (max 200) |
| POST | `/api/v1/workspaces/:wid/channels/:cid/messages` | JWT | Send message |
| PUT | `/api/v1/workspaces/:wid/channels/messages/:mid` | JWT | Edit message |
| DELETE | `/api/v1/workspaces/:wid/channels/messages/:mid` | JWT | Delete message |
| GET | `/api/v1/workspaces/:wid/channels/messages/:mid/thread` | JWT | Get thread replies |
| POST | `/api/v1/workspaces/:wid/channels/messages/:mid/reactions` | JWT | Add reaction |
| DELETE | `/api/v1/workspaces/:wid/channels/messages/:mid/reactions` | JWT | Remove reaction |
| POST | `/api/v1/workspaces/:wid/channels/messages/:mid/pin` | JWT | Pin message |
| DELETE | `/api/v1/workspaces/:wid/channels/messages/:mid/pin` | JWT | Unpin message |
| GET | `/api/v1/workspaces/:wid/channels/:cid/pinned` | JWT | Get pinned messages |
| POST | `/api/v1/workspaces/:wid/channels/messages/:mid/read` | JWT | Mark as read |
| GET | `/api/v1/workspaces/:wid/channels/messages/:mid/reads` | JWT | Get read receipts |

### Bots
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | `/api/v1/workspaces/:wid/bots` | JWT | Create bot |
| GET | `/api/v1/workspaces/:wid/bots` | JWT | List bots |
| GET | `/api/v1/workspaces/:wid/bots/:bid` | JWT | Get bot details |
| PATCH | `/api/v1/workspaces/:wid/bots/:bid` | JWT | Update bot |
| DELETE | `/api/v1/workspaces/:wid/bots/:bid` | JWT | Delete bot |
| POST | `/api/v1/workspaces/:wid/bots/:bid/keys` | JWT | Generate API key |
| GET | `/api/v1/workspaces/:wid/bots/:bid/keys` | JWT | List API keys |
| DELETE | `/api/v1/workspaces/:wid/bots/:bid/keys/:kid` | JWT | Revoke API key |
| POST | `/api/v1/workspaces/:wid/bots/:bid/commands` | JWT | Register command |
| GET | `/api/v1/workspaces/:wid/bots/:bid/commands` | JWT | List commands |
| PATCH | `/api/v1/workspaces/:wid/bots/:bid/commands/:cid` | JWT | Update command |
| DELETE | `/api/v1/workspaces/:wid/bots/:bid/commands/:cid` | JWT | Remove command |
| POST | `/api/v1/workspaces/:wid/bots/:bid/events` | JWT | Subscribe to event |
| GET | `/api/v1/workspaces/:wid/bots/:bid/events` | JWT | List subscriptions |
| DELETE | `/api/v1/workspaces/:wid/bots/:bid/events/:sid` | JWT | Unsubscribe |

### Admin
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/api/v1/workspaces/:wid/members` | JWT | List members (admin view) |
| PATCH | `/api/v1/workspaces/:wid/members/:uid/role` | JWT | Change member role |
| DELETE | `/api/v1/workspaces/:wid/members/:uid` | JWT | Remove member |
| GET | `/api/v1/workspaces/:wid/audit` | JWT | Get audit log (last 100) |
| GET | `/api/v1/workspaces/:wid/storage` | JWT | Storage stats |

### Other
| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/v1/health` | Health check |
| GET | `/api/v1/meet/sessions` | List meetings |
| POST | `/api/v1/meet` | Create meeting |
| POST | `/api/v1/meet/:mid/start` | Start meeting |
| POST | `/api/v1/meet/:mid/end` | End meeting |
| POST | `/api/v1/meet/:mid/join` | Join meeting |
| GET | `/api/v1/meet/:mid/token` | Get LiveKit token |
| POST | `/api/v1/signaling/token` | WebRTC signaling token |
| POST | `/api/v1/vault/:wid/upload` | Upload file to vault |
| GET | `/api/v1/vault/:wid/recent` | Recent vault files |
| GET | `/api/v1/vault/files/:fid` | Download file |
| GET | `/api/v1/workspaces/:wid/search?q=&type=` | Full-text search |
| GET | `/api/v1/updates/check` | Check for app updates |
| GET | `/api/v1/projects/templates` | List project templates |

---

## 8. WebSocket Events

### Chat Gateway (namespace: `/`)
| Event | Direction | Payload |
|-------|-----------|---------|
| `channel.join` | Client→Server | `{ channelId }` |
| `channel.leave` | Client→Server | `{ channelId }` |
| `message.send` | Client→Server | `{ tempId, channelId, content, attachments?, threadId? }` |
| `message.edit` | Client→Server | `{ messageId, content }` |
| `message.delete` | Client→Server | `{ messageId }` |
| `message.read` | Client→Server | `{ messageId, timestamp }` |
| `reaction.add` | Client→Server | `{ channelId, messageId, emoji }` |
| `reaction.remove` | Client→Server | `{ channelId, messageId, emoji }` |
| `message.pin` | Client→Server | `{ channelId, messageId, reason? }` |
| `message.unpin` | Client→Server | `{ channelId, messageId }` |
| `bulletin.create` | Client→Server | workspace bulletin data |
| `message.new` | Server→Client | Full message payload + soundUrl |
| `message.sent` | Server→Client | `{ tempId, messageId, timestamp }` |
| `message.failed` | Server→Client | `{ tempId, error }` |
| `message.edited` | Server→Client | Edited message payload |
| `message.deleted` | Server→Client | `{ messageId, channelId }` |
| `reaction.added` | Server→Client | Reaction event |
| `reaction.removed` | Server→Client | Reaction event |
| `message.read` | Server→Client | Read receipt |
| `message.pinned` | Server→Client | Pin event |
| `bulletin.*` | Server→Client | Bulletin CRUD events |

### Presence Gateway (namespace: `/presence`)
| Event | Direction | Payload |
|-------|-----------|---------|
| `heartbeat` | Client→Server | `{ status? }` |
| `typing` | Client→Server | `{ channelId, typing }` |
| `presence.update` | Server→Client | `{ workspaceId, userId, status }` |
| `user_joined` | Server→Client | `{ userId, displayName, email }` |
| `user_left` | Server→Client | `{ userId, displayName }` |

---

## 9. Bot SDK API

```typescript
import { Bot } from '@flowspace/bot-sdk';

const bot = new Bot({
    apiKey: 'flo_xxxxxxxxxxxx',    // Must start with 'flo_'
    workspaceId: 'workspace-uuid',  // Non-empty string
    serverUrl: 'http://localhost:4000',  // Non-empty string
});

// Lifecycle
await bot.connect();       // Returns Promise, rejects on error
bot.disconnect();          // Synchronous cleanup
bot.isConnected;           // Boolean getter

// Commands (handled via WebSocket, no REST registration needed)
bot.command('/help', async (ctx) => {
    await ctx.reply('Available commands...');
});

// Events
bot.on('message.new', (msg) => { /* BotMessagePayload */ });
bot.on('error', (err) => { /* { type, error, context } */ });

// Messaging
await bot.sendMessage(channelId, 'Hello', [], 15000);  // 15s default timeout
bot.addReaction(channelId, messageId, '👍');            // Fire and forget
```

---

## 10. Files Changed

| File | Changes |
|------|---------|
| `backend/src/auth/auth.service.ts` | bcrypt 8→12, HS256 pinning, email enumeration fix |
| `backend/src/auth/auth.controller.ts` | DTO classes, refresh token ownership check |
| `backend/src/auth/jwt.guard.ts` | Fail-closed for non-HTTP contexts |
| `backend/src/auth/services/token.service.ts` | bcrypt-hash refresh tokens |
| `backend/src/auth/kratos-session.guard.ts` | Identity ID validation |
| `backend/src/bots/bots-auth.guard.ts` | Fail-closed for non-HTTP/non-WS contexts |
| `backend/src/bots/bots.service.ts` | getBotForConnection, persistBotMessage, bcrypt 12 |
| `backend/src/bots/bots.gateway.ts` | Fix 4 P0 bugs, rate limiter, channel validation |
| `backend/src/bots/bots.module.ts` | Import AuthModule |
| `backend/src/bots/dto/bot.dto.ts` | Definite assignment assertions |
| `backend/src/chat/chat.gateway.ts` | Remove anonymous bypass, remove require(), fix stubs, limits |
| `backend/src/chat/chat.service.ts` | Transactions, reaction fix, content limits, pagination |
| `backend/src/presence/presence.gateway.ts` | TTL 30s, heartbeat debounce |
| `backend/src/database/prisma.service.ts` | Remove --accept-data-loss, add $disconnect |
| `backend/prisma/schema.prisma` | Cascade→SetNull, VarChar, indexes, remove dead table |
| `backend/src/shared/redis.service.ts` | Error logging, isHealthy() |
| `backend/src/adapters/redis-io.adapter.ts` | Production fail-fast, error handlers |
| `backend/src/workspaces/workspace-filesystem.service.ts` | Path traversal protection |
| `backend/src/workspaces/workspace-vault-sync.service.ts` | Remove hardcoded creds |
| `backend/src/search/search.module.ts` | Import AuthModule |
| `backend/src/main.ts` | CORS, Helmet, body limits, ValidationPipe, Redis hard-fail |
| `backend/src/app.module.ts` | ThrottlerModule |
| `bot-sdk/src/bot.ts` | Timeout, validation, isConnected, error routing |
| `bot-sdk/src/context.ts` | Attachments support in reply() |
| `README.md` | Remove false claims, honest roadmap |
| `docker-compose.yml` | New: PostgreSQL 16 + Redis 7 |
| `backend/.env` | New: All env vars |
| `backend/config/projectTemplates.json` | New: Template registry |

---

## 11. What Still Needs Attention (Follow-Up)

These are documented as TODOs in the code and are lower priority:

1. **Reaction emoji validation**: Currently limited to 32 chars but not validated against an emoji set
2. **Bulletin persistence**: Bulletins are ephemeral (in-memory, lost on restart) — needs DB model
3. **N+1 query in listChannels**: Last message fetched per channel — should use a window function
4. **Session recovery on reconnect**: Room memberships lost when WebSocket reconnects
5. **API key rotation**: No support for multiple active keys or key rotation without downtime
6. **Bot audit logging**: TODO comments placed at all bot action sites
7. **Token cleanup**: Expired RefreshToken/VerificationToken rows accumulate indefinitely
8. **Connection pool configuration**: Explicit Prisma pool sizing for production deployments
9. **Event deduplication**: README previously claimed LRU cache existed — should implement for real
10. **workspace.activity batching**: Removed due to scaling concerns — needs replacement

---

## 12. Production Deployment Notes

Before deploying to production:

1. **Change JWT_SECRET**: Generate a strong random secret (e.g., `openssl rand -hex 64`)
2. **Set FRONTEND_URL**: Must be the exact URL of your frontend
3. **Set REDIS_URL**: Required. Server will refuse to start without it in production
4. **Configure MinIO/S3**: Set `MINIO_ACCESS_KEY`, `MINIO_SECRET_KEY`, `MINIO_ENDPOINT`, and `MINIO_BUCKET`
5. **Run migrations**: Use `npx prisma migrate deploy` instead of `db push`
6. **Set NODE_ENV=production**: Enables strict CORS/Redis validation and Helmet CSP
7. **Use a process manager**: PM2 or systemd, not `ts-node` directly
