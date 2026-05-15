# AGENTS.md

## Cursor Cloud specific instructions

### Services Overview

| Service | How to run | Port |
|---------|-----------|------|
| Backend (NestJS) | `cd backend && npm run start:dev` | 4000 |
| Bot SDK | `cd bot-sdk && npm run build` | N/A (library) |

### Backend Dev Server

- **Start**: `cd backend && npm run start:dev` (uses nodemon + ts-node)
- **Health check**: `GET http://localhost:4000/api/v1/health`
- **API prefix**: `/api/v1`
- **WebSocket**: `ws://localhost:4000` (Socket.IO)

### Prerequisites (must be running before backend starts)

- **PostgreSQL** on `localhost:5432` — database `flowspace`, user `flowspace`/`flowspace`
- **Redis** on `localhost:6379` — used for Socket.IO horizontal scaling; backend gracefully falls back to in-memory adapter if unavailable

Start services:
```bash
sudo pg_ctlcluster 16 main start
sudo redis-server --daemonize yes
```

### Key Gotchas

1. **Prisma schema requires manual relation fixes**: The `Bot` and `BotMessage` models reference `Workspace`, `Channel`, and `ChatMessage` but the reverse relation fields (`bots Bot[]`, `botMessages BotMessage[]`) must be present on those models. Run `npx prisma generate` after any schema changes.

2. **`projectTemplates.json` required at startup**: The backend TemplateService throws at boot if `backend/config/projectTemplates.json` doesn't exist. A minimal seed file is committed.

3. **Module DI for `JwtAuthGuard`**: Any NestJS module using `@UseGuards(JwtAuthGuard)` must import `AuthModule` (which exports `AuthService`).

4. **`.env` location**: The backend reads environment from `backend/.env` (via `@nestjs/config`). The committed `env.development` uses Docker service hostnames; for local dev, create `.env` with `localhost` addresses (DATABASE_URL, REDIS_URL, etc.).

5. **TypeScript checking**: `npm run build` runs `prisma generate && nest build`. For type-only checking use `npx tsc --noEmit` from the backend directory.

6. **No ESLint configured**: The project does not have an ESLint config. TypeScript compilation (`tsc --noEmit`) is the primary static analysis.

7. **MinIO/S3 and LiveKit are optional**: File vault and video meeting features require these services but the backend starts fine without them.

### Test Account (local dev)

```
Email: dev@flowspace.app
Password: TestPass123!
```

Or register via `POST /api/v1/auth/register` with `{ email, password, name }`.

### Flutter Client

The Flutter client (`client_flutter/`) targets desktop (Windows primary) and mobile. It requires the Flutter SDK and cannot be run in headless Cloud Agent environments. Focus backend development on the NestJS API server.
