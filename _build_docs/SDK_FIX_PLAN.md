# Target
Fix bot-sdk/src/bot.ts, bot-sdk/src/context.ts

# Changes (apply EVERY one):

## bot.ts

### P0: Add timeout to sendMessage (lines ~95-129)
Wrap the Promise in Promise.race with a timeout:
```typescript
sendMessage(channelId: string, content: string, attachments?: string[], timeoutMs = 15000): Promise<void> {
    return new Promise<void>((resolve, reject) => {
      if (!this.socket?.connected) {
        reject(new Error('Bot is not connected'));
        return;
      }

      const payload: Record<string, unknown> = { channelId, content };
      if (attachments?.length) payload.attachments = attachments;

      let timedOut = false;
      const timer = setTimeout(() => {
        timedOut = true;
        cleanup();
        reject(new Error(`sendMessage timed out after ${timeoutMs}ms`));
      }, timeoutMs);

      const onConfirmed = (_data: { messageId: string }) => {
        if (timedOut) return;
        cleanup();
        resolve();
      };
      const onFailed = (data: { error: string }) => {
        if (timedOut) return;
        cleanup();
        reject(new Error(data.error ?? 'Failed to send message'));
      };

      const cleanup = () => {
        clearTimeout(timer);
        this.socket?.off('message.confirmed', onConfirmed);
        this.socket?.off('message.failed', onFailed);
      };

      this.socket.emit('message.send', payload);
      this.socket.once('message.confirmed', onConfirmed);
      this.socket.once('message.failed', onFailed);
    });
}
```

### P1: Command handler errors — emit to an error handler instead of swallowing
Change the command.invoked listener: instead of empty catch, emit to an 'error' handler:
```typescript
this.socket.on('command.invoked', (payload: CommandPayload) => {
    const handler = this.commands.get(payload.command);
    if (handler) {
      const ctx = new CommandContext(this, payload);
      try {
        const result = handler(ctx);
        if (result instanceof Promise) {
          result.catch((err) => {
            this._emitError('command_error', err, payload);
          });
        }
      } catch (err) {
        this._emitError('command_error', err, payload);
      }
    }
});
```

Add private method:
```typescript
private _emitError(type: string, err: unknown, context?: unknown): void {
    const handlers = this.eventHandlers.get('error');
    if (handlers) {
      for (const h of handlers) {
        try { h({ type, error: err, context }); } catch {}
      }
    }
}
```

### P1: Validate BotOptions in constructor
```typescript
constructor(options: BotOptions) {
    if (!options.apiKey || typeof options.apiKey !== 'string' || !options.apiKey.startsWith('flo_')) {
      throw new Error('Invalid apiKey: must be a non-empty string starting with "flo_"');
    }
    if (!options.workspaceId || typeof options.workspaceId !== 'string') {
      throw new Error('Invalid workspaceId: must be a non-empty string');
    }
    if (!options.serverUrl || typeof options.serverUrl !== 'string') {
      throw new Error('Invalid serverUrl: must be a non-empty string');
    }
    this.apiKey = options.apiKey;
    this.workspaceId = options.workspaceId;
    this.serverUrl = options.serverUrl;
}
```

### P2: Expose connected state
Add getter:
```typescript
get isConnected(): boolean {
    return this.socket?.connected ?? false;
}
```

### P2: Add typed event payloads
Add interfaces:
```typescript
export interface BotConnectedPayload { botId: string; workspaceId: string; }
export interface BotErrorPayload { message: string; }
export interface BotMessagePayload { id: string; channelId: string; senderId: string; senderName: string; content: string; attachments?: string[]; parentId?: string; timestamp: string; isBot?: boolean; botId?: string; }
```
Replace `type EventHandler = (data: any) => ...` keep as any for flexibility but add comment documenting known event payloads.

### P2: Fix connectPromise poisoning
In the 'error' handler, null out connectPromise so subsequent connect() calls start fresh:
```typescript
this.socket.once('error', (err: { message: string }) => {
    this.connectPromise = null;
    reject(new Error(err.message ?? 'Bot connection rejected'));
});
```

Also reset on disconnect (add disconnect listener that nulls connectPromise).

## context.ts

### P1: Add attachments support to reply()
```typescript
async reply(content: string, attachments?: string[]): Promise<void> {
    await this.bot.sendMessage(this.channelId, content, attachments);
}
```
