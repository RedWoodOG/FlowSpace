# Target
Fix prisma.service.ts, schema.prisma, redis.service.ts, redis-io.adapter.ts

# Changes (apply EVERY one):

## prisma.service.ts

### P0: REMOVE --accept-data-loss entirely
Delete the runMigrations() method entirely. Replace onModuleInit with:
```typescript
async onModuleInit() {
    await this.$connect();
}
```
Remove the exec imports and execAsync at top of file. Remove ensurePrismaClient() method. Remove enableShutdownHooks as it doesn't work properly.

### P0: Add $disconnect
Add:
```typescript
async onModuleDestroy() {
    await this.$disconnect();
}
```

### P1: Remove child_process.exec for prisma generate
Remove ensurePrismaClient() entirely. Prisma client generation should happen at BUILD TIME. Add a comment: `// Run 'npx prisma generate' before building — not at runtime`.

## schema.prisma

### P1: Remove cascade delete on ChatMessage parent
Change line ~102 from `onDelete: Cascade` to `onDelete: SetNull`:
```
parent      ChatMessage?  @relation("MessageThread", fields: [parentId], references: [id], onDelete: SetNull)
```

### P2: Add content length constraint
Change ChatMessage.content from `String` to `String @db.VarChar(50000)`:
```
content     String        @db.VarChar(50000)
```

### P2: Add compound index for soft-delete filtering
Add index:
```
@@index([channelId, deleted, createdAt])
```

### P2: Remove dead PresenceSnapshot model
Delete the entire PresenceSnapshot model (lines ~121-128). It's dead code — presence is managed in Redis.

## redis.service.ts

### P0: Stop silently swallowing errors
In constructor error handlers: change `console.debug` to `this.logger.error()` (add Logger). Stop filtering errors by type — log ALL errors at error level.
Remove `catch(() => {})` from connect calls. Instead: `this.publisher.connect().catch(err => { this.logger.error('Redis publisher failed to connect:', err.message); });`

### P0: Add health check method
```typescript
isHealthy(): boolean {
    return this.publisher.status === 'ready' && this.subscriber.status === 'ready';
}
```

### P0: Make publish throw on failure
Remove the try/catch that returns 0 silently. Let errors propagate. Callers should handle them:
```typescript
async publish(channel: string, payload: unknown): Promise<number> {
    const message = typeof payload === 'string' ? payload : JSON.stringify(payload);
    return this.publisher.publish(channel, message);
}
```

Actually, for backward compatibility: keep the graceful fallback but log errors. Add a `publishOrThrow` method that throws.

Let's compromise: keep publish() graceful but add error logging. Add a second method `publishRequired()` that throws. Use publishRequired() in critical paths (message send, presence update).

## redis-io.adapter.ts

### P0: No silent fallback in production
In connectToRedis(): if REDIS_URL is not set, check NODE_ENV. If production, throw Error. If development, log warning and use in-memory.
```typescript
if (!redisUrl) {
    if (process.env.NODE_ENV === 'production') {
        throw new Error('REDIS_URL is required in production for multi-instance Socket.IO');
    }
    this.logger.warn('REDIS_URL not set — using in-memory adapter (single instance only)');
    return;
}
```

### P1: Add error handlers to pubClient/subClient
After creating pubClient/subClient, add:
```typescript
pubClient.on('error', (err) => { this.logger.error('Redis pubClient error:', err.message); });
subClient.on('error', (err) => { this.logger.error('Redis subClient error:', err.message); });
```

## workspace-filesystem.service.ts

### P1: Add path traversal protection
In getWorkspacePath: after path.join, add:
```typescript
const resolved = path.resolve(baseWorkspacePath, workspaceSlug);
if (!resolved.startsWith(path.resolve(baseWorkspacePath))) {
    throw new ForbiddenException('Invalid workspace path');
}
return resolved;
```

## workspace-vault-sync.service.ts

### P2: Remove hardcoded MinIO credentials
Change `accessKeyId: 'minioadmin'` etc to throw if not configured:
```typescript
const accessKey = this.config.get<string>('MINIO_ACCESS_KEY');
const secretKey = this.config.get<string>('MINIO_SECRET_KEY');
if (!accessKey || !secretKey) {
    throw new Error('MINIO_ACCESS_KEY and MINIO_SECRET_KEY must be configured');
}
```
