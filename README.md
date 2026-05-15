# FlowSpace

FlowSpace is a private company collaboration platform — Slack, Teams, and Zoom capabilities in one cross-platform experience: workspaces, streams, meetings, file vault, projects, bots, search, and admin tools.

**License**: Proprietary. See [LICENSE](LICENSE). Unauthorized use, distribution, or sublicensing is prohibited.

---

## Latest Release

**v2.1.0** — Windows x64

[Download FlowSpace v2.1.0](https://github.com/VYRE-Studios/FlowSpace/releases/download/v2.1.0/FlowSpace-v2.1.0-Windows-x64.zip)

Local-first by default with server-ready connection settings for self-hosted deployments.

---

## Features

### Core Platform
- **Workspaces** — Multi-workspace navigation with slug-based URLs and member management
- **Streams** — Real-time channels with threads, reactions, pins, read receipts, typing indicators
- **Connect** — LiveKit-powered video meetings with scheduling and participant management
- **Vault** — File upload, download, and management per workspace with S3/MinIO backend
- **Calendar** — Meeting scheduling and calendar integration
- **Projects** — Kanban boards, storyboards, project manifests with template system
- **Presence** — Online/away/busy/offline status with real-time heartbeat

### Bots & Automation (NEW)
- **Bot Accounts** — Create bot users per workspace with API key authentication
- **Slash Commands** — Register `/command` handlers processed in real-time
- **WebSocket Runtime** — Bots connect via Socket.IO with API key auth
- **Webhook Handlers** — Optional HTTP webhook dispatch for bot commands
- **Event Subscriptions** — Bots listen to `message.new`, `user.joined`, `channel.created`, reactions, and mentions
- **Bot SDK** — TypeScript package (`@flowspace/bot-sdk`) for building custom bots

### Administration (NEW)
- **Member Management** — Invite, remove, and manage workspace members
- **Role-Based Access** — OWNER, ADMIN, MEMBER roles with granular permissions
- **Audit Log** — Full audit trail of workspace actions with entity tracking
- **Storage Dashboard** — Workspace storage usage and file statistics
- **Bot Management UI** — Create, configure, and monitor bots from workspace settings
- **API Key Management** — Generate, list, and revoke bot API keys

### Search (NEW)
- **Full-Text Search** — Search across messages, files, and projects
- **Workspace-Scoped** — Results filtered by workspace membership
- **Multi-Type** — Filter by messages, files, projects, or all

### Realtime Infrastructure
- **JWT-Authenticated WebSocket** — Secure Socket.IO connections with token validation
- **Exponential Backoff** — Automatic reconnection with 1s→30s backoff
- **Redis Pub/Sub** — Horizontally scalable event dispatch across server instances (requires REDIS_URL)

### Cross-Platform Client
- **Windows** — Primary target with NSIS installer and portable builds
- **macOS** — Desktop target with local SQLite support
- **Linux** — Desktop target for self-hosted deployments
- **iOS / Android** — Mobile targets for future validation

---

## Server-Ready Mode

Connection modes in `Settings > Connection`:

- **Local** — Offline-first; accounts and data stored in SQLite on-device
- **Self-hosted Server** — Points at a shared FlowSpace backend

Server mode health check: `GET /api/v1/health`

Default local account:

```
Email: local@flowspace.app
Password: flowspace123
```

---

## Tech Stack

### Frontend
- Flutter / Dart
- Windows, macOS, Linux, iOS, Android targets
- SQLite via `sqflite_common_ffi`
- Provider pattern state management
- Secure storage via `flutter_secure_storage`

### Backend
- NestJS (TypeScript)
- Prisma ORM + PostgreSQL
- Redis for pub/sub and Socket.IO scaling
- Socket.IO for real-time communication
- LiveKit for video meetings
- AWS S3 / MinIO for file storage
- JWT authentication with refresh tokens

---

## Bot SDK

Build bots for FlowSpace with the official TypeScript SDK:

```typescript
import { Bot } from '@flowspace/bot-sdk';

const bot = new Bot({
  apiKey: 'flo_xxxxxxxxxxxx',
  workspaceId: 'your-workspace-id',
  serverUrl: 'https://flowspace.yourcompany.com',
});

bot.command('/help', async (ctx) => {
  await ctx.reply('Available commands: /help, /poll, /standup');
});

bot.on('user.joined', async (user) => {
  await bot.sendMessage('general', `Welcome ${user.userName}! 🎉`);
});

await bot.connect();
```

See [Bot Architecture](docs/BOT_ARCHITECTURE.md) for full API reference and design.

---

## Repository Layout

```
FlowSpace/
  backend/                  NestJS API server
  ├── src/auth/             JWT auth, email verification
  ├── src/chat/             Channels, messages, threads, reactions, pins
  ├── src/workspaces/       Workspace CRUD, membership, file-system
  ├── src/vault/            File upload, download, management
  ├── src/meet/             LiveKit meeting scheduling
  ├── src/presence/         Real-time presence heartbeat
  ├── src/bots/             Bot management, API keys, command routing (NEW)
  ├── src/admin/            Member management, audit log, storage (NEW)
  ├── src/search/           Full-text search across entities (NEW)
  ├── src/signaling/        WebRTC signaling relay
  ├── src/p2p-gateway/      P2P message gateway
  ├── src/p2p-runtime/      P2P runtime service
  ├── src/projects/         Project templates and boards
  ├── src/updates/          App update system
  └── prisma/               Database schema and migrations
  client_flutter/           Flutter desktop/mobile app
  ├── lib/services/         API clients and backend integrations
  ├── lib/ui/screens/       App screens (bots, streams, vault, etc.)
  ├── lib/ui/views/         View components
  ├── lib/ui/widgets/       Reusable widgets
  ├── lib/models/           Data models
  ├── lib/providers/        State management providers
  ├── lib/sync/             Real-time sync engine
  └── lib/navigation/       App routing
  bot-sdk/                  TypeScript Bot SDK package (NEW)
  docs/                     Architecture plans and screenshots
  documents/                Implementation notes and deployment guides
  infrastructure/           Docker and nginx configs
  scripts/windows/          Windows helper and packaging scripts
```

---

## Run Locally

### Backend
```bash
cd backend
npm install
npx prisma generate
npm run start:dev
```

### Flutter Client
```bash
cd client_flutter
flutter pub get
flutter run -d windows
```

---

## Roadmap Status

| System | Status |
|--------|--------|
| Backend build | 🟢 Green |
| Flutter / Dart toolchain | 🟢 Green |
| Android build | 🟢 Green |
| App boot | 🟡 Yellow |
| Auth (JWT + refresh) | 🟡 Yellow |
| Workspace management | 🟢 Green |
| Streams (chat, threads, reactions) | 🟢 Green |
| Realtime (Socket.IO + dedup) | 🟡 Yellow |
| Connect (LiveKit meetings) | 🟡 Yellow |
| Vault (file storage) | 🟡 Yellow |
| Presence (heartbeat + status) | 🟡 Yellow |
| Notifications | 🟡 Yellow |
| Projects (templates + boards) | 🟡 Yellow |
| Bots & automation | 🟡 Yellow |
| Admin (members, roles, audit) | 🟢 Green |
| Search (full-text) | 🟢 Green |
| Release workflow | 🟡 Yellow |

Full plan: [All Systems Green Plan](docs/FLOWSPACE_ALL_SYSTEMS_GREEN_PLAN.md)

---

## License

**Proprietary — All Rights Reserved.**

This software is the exclusive property of VyreVault Studios. Use, modification, and distribution are strictly limited. See [LICENSE](LICENSE) for full terms.

Unauthorized use, copying, distribution, or creation of derivative works is prohibited and will be prosecuted.
