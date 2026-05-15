# FlowSpace Hardening Report — Council Review
**Date**: 2026-05-14  
**Reviewers**: 5 subagent council (Auth/Security, Backend Architecture, Realtime Infrastructure, Data Layer, Bot SDK)  
**Overall Verdict**: **NOT PRODUCTION-READY** — 13 CRITICAL, 21 HIGH, 15 MEDIUM findings

---

## Executive Summary

Five specialized reviewers independently audited the FlowSpace codebase. Every reviewer returned a verdict of **incorrect** — the system has systemic gaps across authentication, real-time messaging, data integrity, and the bot subsystem. Four of the five subsystems deemed "🟢 Green" in the README roadmap (Bots, Admin, Search, Realtime) have critical issues that make them non-functional or dangerous in production.

### Critical Themes

1. **Authentication is bypassable** — The WebSocket gateway admits unauthenticated clients with hardcoded test credentials
2. **Silent failure is the default** — Redis errors, auth errors, webhook failures, and bot command failures are all silently swallowed
3. **The bot subsystem is non-functional** — Four independent P0 bugs mean bots cannot connect, cannot receive commands, and their messages never reach users
4. **Data destruction is automatic** — `prisma db push --accept-data-loss` runs on every startup
5. **No rate limiting exists anywhere** — Every endpoint (HTTP and WebSocket) accepts unbounded input
6. **README claims are false** — The advertised "LRU-based dedup cache" does not exist in code

---

## CRITICAL Findings (P0) — 13 total

### C1. Anonymous user bypass in ChatGateway
**Files**: `backend/src/chat/chat.gateway.ts:97-109`  
**Found by**: Auth, BackendArch, RealtimeInfra (3 reviewers)

`handleConnection` catches JWT auth errors and silently assigns a hardcoded anonymous user (`id: 'anonymous', email: 'test@flowspace.local'`) instead of disconnecting. Any unauthenticated client providing a valid `workspaceId` query param gains full messaging, reaction, pinning, and bulletin capabilities.

**Fix**: Delete the catch block. Call `client.disconnect(true)` on auth failure. Remove the "TEMPORARY testing mode" comment — it's live code.

---

### C2. JwtAuthGuard silently passes non-HTTP contexts
**File**: `backend/src/auth/jwt.guard.ts:19-22`  
**Found by**: Auth

`canActivate` returns `true` unconditionally when `context.getType() !== 'http'`. If this guard is ever applied to a WebSocket or RPC context (even accidentally), authentication is bypassed.

**Fix**: Change non-HTTP branch to `throw new UnauthorizedException('JWT guard only supports HTTP contexts')`.

---

### C3. CORS wildcard fallback with credentials:true
**File**: `backend/src/main.ts:13-24`  
**Found by**: Auth

The origin array contains `process.env.FRONTEND_URL || '*'` with `credentials: true`. The wildcard `*` combined with `credentials: true` is a browser-enforced error, but the broader issue is `https://*.onrender.com` and `https://*.railway.app` — any subdomain on those platforms can make credentialed cross-origin requests.

**Fix**: Remove `'*'` fallback. Validate `FRONTEND_URL` at startup and crash if unset. Restrict platform wildcards to specific subdomains you control.

---

### C4. Refresh tokens stored in plaintext
**File**: `backend/src/auth/services/token.service.ts:45-54`  
**Found by**: Auth

`saveRefreshToken` stores the raw `crypto.randomBytes(40).toString('hex')` value directly in the database. A database breach exposes every refresh token in immediately-usable form.

**Fix**: bcrypt-hash refresh tokens before storage (matching the API key pattern). Return the raw token once; store only the hash.

---

### C5. No rate limiting on any auth endpoint
**Files**: `backend/src/auth/auth.controller.ts:1-114`  
**Found by**: Auth

Login, register, refresh, and verify-email endpoints have zero rate limiting. Brute-force at line speed. Email enumeration possible via differential error responses (ConflictException vs UnauthorizedException).

**Fix**: Apply `@nestjs/throttler` with strict per-IP windows: 5 attempts/15min on login, 3 registrations/hour/IP, 10 refresh attempts/minute.

---

### C6. RedisService silently suppresses all errors
**File**: `backend/src/shared/redis.service.ts:61-108`  
**Found by**: BackendArch, RealtimeInfra, BotSDK (3 reviewers)

The constructor uses empty `catch(() => {})` blocks. `publish()` returns 0 silently on failure (same as "0 subscribers" — ambiguous). `subscribe()` catches and discards errors. The entire pub/sub layer can fail with zero indication. The application appears to run normally while all real-time features are dead.

**Fix**: Log errors at `error` level. Expose a `isHealthy(): boolean` method. Make `publish()` throw or return a discriminated result. Add a health-check endpoint that verifies Redis connectivity.

---

### C7. Silent fallback to in-memory Socket.IO adapter
**File**: `backend/src/adapters/redis-io.adapter.ts:13-26`  
**Found by**: RealtimeInfra

When `REDIS_URL` is unset, the adapter silently degrades to in-memory mode. In multi-instance deployments, this means cross-instance message delivery fails silently — clients on different instances cannot see each other's messages, reactions, or presence.

**Fix**: Add a startup assertion. If `NODE_ENV === 'production'` and `REDIS_URL` is missing, crash with a clear error message. Never silently degrade in production.

---

### C8. `prisma db push --accept-data-loss` on every startup
**File**: `backend/src/database/prisma.service.ts:63-102`  
**Found by**: DataLayer

This runs on every `onModuleInit()` — every application startup, including production. It WILL silently drop columns, tables, and reshape the database with no confirmation. There is no environment check or safeguard.

**Fix**: Remove entirely. Replace with versioned `prisma migrate deploy` that runs only forward migrations. Gate behind an explicit `--run-migrations` flag or environment check. Never use `--accept-data-loss` in any context.

---

### C9. PrismaService never calls $disconnect — connection leak
**File**: `backend/src/database/prisma.service.ts:9-18`  
**Found by**: DataLayer

No `onModuleDestroy` or `onApplicationShutdown` hook exists. On every graceful shutdown, Prisma's connection pool is not drained, leaking TCP connections. Under container orchestration with rolling restarts, this causes connection exhaustion.

**Fix**: Add `onModuleDestroy() { await this.$disconnect(); }`.

---

### C10. Bot messages never reach users — Redis channel name mismatch
**File**: `backend/src/bots/bots.gateway.ts:117-120`  
**Found by**: BotSDK

BotsGateway publishes to `'message.sent'` but ChatGateway subscribes to `WorkspaceEvents.MESSAGE_SENT` which is `'workspace.message.sent'`. Different channel names. Bot messages are persisted but never broadcast.

**Fix**: Use `WorkspaceEvents.MESSAGE_SENT` constant in BotsGateway.

---

### C11. Bot command routing is a dead letter
**File**: `backend/src/chat/chat.gateway.ts:185-195`  
**Found by**: BotSDK

ChatGateway publishes `'command.invoked'` to Redis, but no code subscribes to this channel. `dispatchCommandToBot` exists but is never called. Slash commands are silently dropped — the user gets a fake acknowledgment.

**Fix**: Add `onModuleInit` to BotsGateway that subscribes to `'command.invoked'` and calls `dispatchCommandToBot`.

---

### C12. Bot connections always rejected
**File**: `backend/src/bots/bots.gateway.ts:46-51`  
**Found by**: BotSDK

`handleConnection` calls `getBot(workspaceId, botId, 'system')` to bypass membership, but `getBot` unconditionally calls `requireMember(workspaceId, 'system')` which throws `ForbiddenException`. The `.catch(() => null)` swallows it, `bot` becomes null, and the bot is disconnected. All bot connections are rejected.

**Fix**: Add `getBotInternal()` method that skips membership check, or pass a flag to `getBot()`.

---

### C13. Bot SDK sendMessage Promise hangs forever
**File**: `bot-sdk/src/bot.ts:95-129`  
**Found by**: BotSDK

No timeout on the Promise wrapping `message.send`. If the server crashes before responding, the Promise hangs forever — `await` never returns, no error, no retry.

**Fix**: `Promise.race` against a configurable timeout (10-30s), reject with descriptive error, ensure cleanup runs.

---

## HIGH Findings (P1) — 21 total

### H1. bcrypt at 8 rounds (should be 12)
**Files**: `auth.service.ts:91`, `auth.service.ts:138`, `bots.service.ts:125`  
**Found by**: Auth

At 8 rounds, a single GPU computes ~100K hashes/sec. At 12 rounds: ~3-5/sec. Use 12 rounds everywhere.

---

### H2. API key prefix-matching side channel
**File**: `backend/src/bots/bots.service.ts:125-129`  
**Found by**: Auth

15-char prefix stored in plaintext. Attacker can brute-force prefixes to discover key existence, then target bcrypt comparisons.

**Fix**: Use 12 rounds. Add a key ID (UUID) for lookup alongside the secret.

---

### H3. JWT algorithm not pinned to HS256
**Files**: `auth.service.ts:69-70`, all JwtModule registrations  
**Found by**: Auth

Algorithm confusion attacks possible. Pin `algorithms: ['HS256']` on all verify calls and `signOptions: { algorithm: 'HS256' }` in JwtModule configs.

---

### H4. No refresh token rotation
**File**: `backend/src/auth/services/token.service.ts:57-72`  
**Found by**: Auth

`validateRefreshToken` doesn't revoke the old token. A stolen token has a 7-day unlimited-use window. Implement rotation: delete old, issue new. Track token family for replay detection.

---

### H5. Logout doesn't verify refresh token ownership
**File**: `backend/src/auth/auth.controller.ts:108-114`  
**Found by**: Auth

Any authenticated user can revoke any refresh token by guessing token values. Add ownership check: `token.userId === request.user.id`.

---

### H6. BotAuthGuard silently passes non-HTTP contexts
**File**: `backend/src/bots/bots-auth.guard.ts:34-36`  
**Found by**: Auth

Same pattern as JwtAuthGuard. Fail-closed for unknown context types.

---

### H7. WebSocket CORS is wildcard (`cors: true`)
**Files**: `chat.gateway.ts:25`, `presence.gateway.ts:31`, `bots.gateway.ts:15`  
**Found by**: Auth

Allows WebSocket connections from any origin. Combined with C1 (anonymous bypass), this is an open door. Restrict to `FRONTEND_URL`.

---

### H8. Reaction add/remove race condition
**File**: `backend/src/chat/chat.service.ts:270-330`  
**Found by**: BackendArch

Read-modify-write cycle on JSON column without transactions. Concurrent reactions cause silent data loss.

**Fix**: Transaction with optimistic locking, or migrate reactions to a separate table with DB-level uniqueness constraints.

---

### H9. Bulletin system has zero authorization
**File**: `backend/src/chat/chat.gateway.ts:365-410`  
**Found by**: BackendArch

Any connected socket can create/update/delete/pin bulletins for any workspace. `workspaceId` taken from client message body, not validated against membership. `data: any` with zero validation.

**Fix**: Validate `workspaceId` against `client.data.user` membership. Add DTOs. Add database persistence.

---

### H10. Runtime `require()` in TypeScript code
**File**: `backend/src/chat/chat.gateway.ts:157-168, 200-216`  
**Found by**: BackendArch, BotSDK

`require('../bots/bots.gateway')` is dead code (never used). `require('https')` and `require('url')` should be top-level imports.

---

### H11. Direct Prisma access via bracket notation
**File**: `backend/src/bots/bots.gateway.ts:96-108`  
**Found by**: BackendArch, BotSDK

`this.botsService['prisma']` bypasses the service layer and TypeScript access modifiers. Move persistence into a `BotsService.sendBotMessage()` method.

---

### H12. No message content length validation
**Files**: `chat.gateway.ts`, `chat.service.ts:228-245`  
**Found by**: BackendArch, RealtimeInfra

Arbitrary-length content accepted and stored. Multi-gigabyte message payloads possible. Add 50KB limit.

---

### H13. Non-atomic message send
**File**: `backend/src/chat/chat.service.ts:260-275`  
**Found by**: BackendArch

Message creation and `channel.update` are separate DB operations. Crash between them creates ghost messages. Wrap in transaction.

---

### H14. Absence of event deduplication
**File**: `backend/src/common/events/event-bus.ts:1-9`  
**Found by**: RealtimeInfra

README claims "LRU-based dedup cache" — this is false. `event-bus.ts` is a 7-line bare `EventEmitter`. No dedup exists anywhere. Remove the false claim from README or implement deduplication.

---

### H15. Presence TTL of 60s with no graceful degradation
**File**: `backend/src/presence/presence.gateway.ts:31-42`  
**Found by**: RealtimeInfra

60 seconds of stale presence after crash. `setStatus()` silently swallows Redis failures. No debounce on heartbeats.

---

### H16. workspace.activity fans out to entire workspace
**File**: `backend/src/chat/chat.gateway.ts:48-60`  
**Found by**: RealtimeInfra

Every message triggers an emission to every workspace member. At 1000+ members, this is O(N×M) self-DoS. Add batching or sampling.

---

### H17. RedisIoAdapter clients have no error handlers
**File**: `backend/src/adapters/redis-io.adapter.ts:18-26`  
**Found by**: RealtimeInfra

Unhandled `error` events on pubClient/subClient crash the Node.js process. Add error handlers.

---

### H18. No session recovery on reconnect
**Files**: `chat.gateway.ts:93-120`, `bots.gateway.ts:28-82`  
**Found by**: RealtimeInfra

Room memberships and client state silently lost on reconnect. Client must manually re-join every channel. Add session store.

---

### H19. `child_process.exec` for prisma generate at runtime
**File**: `backend/src/database/prisma.service.ts:22-59`  
**Found by**: DataLayer

Security risk (shell injection), blocks startup for 15s, runs on every init including tests. Move to build-time (`postinstall` script).

---

### H20. No migration versioning — `prisma db push` only
**File**: `backend/src/database/prisma.service.ts:63-65`  
**Found by**: DataLayer

No `prisma/migrations/` directory. No rollback, no audit trail, no CI testing. Adopt `prisma migrate`.

---

### H21. Recursive cascade delete on ChatMessage threads
**File**: `backend/prisma/schema.prisma:102`  
**Found by**: DataLayer

`onDelete: Cascade` on parent relation. Deleting a thread root cascades to all replies recursively. Change to `SetNull` or `NoAction`.

---

## MEDIUM Findings (P2) — 15 total

1. **Missing Helmet middleware** (`main.ts:8-10`) — No CSP, HSTS, X-Frame-Options headers
2. **Missing CSRF protection** (`main.ts:8-10`) — `credentials: true` without CSRF tokens
3. **No explicit body size limits** (`main.ts:8-10`) — Express defaults not explicitly configured
4. **KratosSessionGuard no identity validation** (`kratos-session.guard.ts:22-50`) — Missing `identity.id` existence check
5. **No DTOs on auth endpoints** (`auth.controller.ts:11-114`) — `class-validator` in deps but unused
6. **Email enumeration via registration** (`auth.service.ts:80-89`) — ConflictException leaks email existence
7. **Duplicate extractUser in ChatGateway and PresenceGateway** — 70-line method duplicated verbatim
8. **Duplicate requireAdmin/requireMember in AdminService and BotsService** — Identical code, guaranteed to drift
9. **N+1 query in listChannels** (`chat.service.ts:38-60`) — Last message fetched per channel
10. **Bulletin system entirely ephemeral** — No persistence, lost on restart
11. **Reaction emoji no validation** (`chat.gateway.ts:235-258`) — Arbitrary strings accepted
12. **Webhook dispatch errors silently swallowed** (`chat.gateway.ts:169-190`) — Fake success acknowledgment
13. **Unbounded getThreadMessages** (`chat.service.ts:508-512`) — No pagination, OOM on large threads
14. **Path traversal risk in workspace slug** (`workspace-filesystem.service.ts:32-35`) — No `path.resolve` prefix check
15. **Hardcoded MinIO admin credentials** (`workspace-vault-sync.service.ts:28-32`) — `minioadmin:minioadmin` defaults

---

## Hardening Plan — Phased Approach

### Phase 1: Stop the Bleeding (P0s only — before any deployment)

| # | Fix | Files |
|---|-----|-------|
| 1 | Remove anonymous user bypass — disconnect on auth failure | `chat.gateway.ts:97-109` |
| 2 | JwtAuthGuard fail-closed for non-HTTP | `jwt.guard.ts:19-22` |
| 3 | Fix CORS origins — remove `*`, restrict platform wildcards | `main.ts:13-24` |
| 4 | bcrypt-hash refresh tokens | `token.service.ts:45-54` |
| 5 | Add rate limiting to auth endpoints | `auth.controller.ts`, `app.module.ts` |
| 6 | Fix Redis error suppression — log errors, add health check | `redis.service.ts:61-108` |
| 7 | Remove silent Redis adapter fallback in production | `redis-io.adapter.ts`, `main.ts` |
| 8 | Remove `--accept-data-loss`, adopt `prisma migrate deploy` | `prisma.service.ts:63-102` |
| 9 | Add `$disconnect` on shutdown | `prisma.service.ts:9-18` |
| 10 | Fix bot message channel name | `bots.gateway.ts:117-120` |
| 11 | Add `command.invoked` Redis subscriber in BotsGateway | `bots.gateway.ts` |
| 12 | Fix bot connection rejection (add `getBotInternal`) | `bots.service.ts`, `bots.gateway.ts` |
| 13 | Add timeout to bot SDK sendMessage | `bot-sdk/src/bot.ts:95-129` |

### Phase 2: Harden (P1s)

- bcrypt 8→12 everywhere
- API key lookup: add key ID, remove prefix side channel
- Pin JWT algorithm to HS256
- Refresh token rotation
- Fix logout ownership check
- BotAuthGuard fail-closed
- Restrict WebSocket CORS origins
- Reaction race condition: transactions or separate table
- Bulletin authorization + persistence
- Remove runtime `require()`, fix imports
- Move bot persistence into service layer
- Add message content length limits (50KB)
- Transactional message send
- Implement or remove README dedup claim
- Presence: reduce TTL, add debounce, handle Redis failure
- Batch workspace.activity emissions
- Add error handlers to RedisIoAdapter clients
- Session recovery on reconnect
- Build-time prisma generate

### Phase 3: Polish (P2s)

- Helmet, CSRF, body size limits
- DTOs with class-validator on all endpoints
- Fix email enumeration
- Extract shared `extractUser` and permission helpers
- Fix N+1 queries
- Persist bulletins to database
- Validate reaction emoji
- Proper webhook error handling
- Paginate thread messages
- Path traversal hardening
- Remove hardcoded MinIO credentials
- Remove dead `PresenceSnapshot` table

---

## False README Claims to Fix Immediately

1. **"Event Deduplication — LRU-based dedup cache prevents duplicate events"** — Does not exist. Remove or implement.
2. **"JWT-Authenticated WebSocket — Secure Socket.IO connections with token validation"** — Bypassed by anonymous fallback.
3. **"Bot Accounts — Create bot users per workspace with API key authentication"** — Bots cannot connect (C12), commands are dead letters (C11), messages never reach users (C10).
4. **"Exponential Backoff — Automatic reconnection with 1s→30s backoff"** — Reconnection exists but session state is lost (H18), no resume mechanism.

---

*End of report. All findings are reproducible from the source files referenced. No findings are speculative.*
