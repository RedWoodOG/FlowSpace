import { io, Socket } from 'socket.io-client';
import { CommandContext, CommandPayload } from './context';

export interface BotOptions {
  apiKey: string;
  workspaceId: string;
  serverUrl: string;
}

type CommandHandler = (ctx: CommandContext) => void | Promise<void>;
type EventHandler = (data: any) => void | Promise<void>;

export class Bot {
  private readonly apiKey: string;
  private readonly workspaceId: string;
  private readonly serverUrl: string;

  private socket: Socket | null = null;
  private readonly commands = new Map<string, CommandHandler>();
  private readonly eventHandlers = new Map<string, Set<EventHandler>>();

  /** Resolved when the `connected` event fires; rejected on `error`. */
  private connectPromise: Promise<void> | null = null;

  constructor(options: BotOptions) {
    this.apiKey = options.apiKey;
    this.workspaceId = options.workspaceId;
    this.serverUrl = options.serverUrl;
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  connect(): Promise<void> {
    if (this.socket?.connected) {
      return Promise.resolve();
    }

    if (this.connectPromise) {
      return this.connectPromise;
    }

    this.connectPromise = new Promise<void>((resolve, reject) => {
      this.socket = io(this.serverUrl, {
        auth: { token: this.apiKey },
        query: { workspaceId: this.workspaceId },
        reconnection: true,
        reconnectionAttempts: Infinity,
        reconnectionDelay: 1000,
        reconnectionDelayMax: 30000,
      });

      // Attach all queued event handlers to the fresh socket
      this._attachEventHandlers();

      this.socket.once('connected', (_data: { botId: string; workspaceId: string }) => {
        resolve();
      });

      this.socket.once('error', (err: { message: string }) => {
        reject(new Error(err.message ?? 'Bot connection rejected'));
      });

      // Wire up `command.invoked` listener
      this.socket.on('command.invoked', (payload: CommandPayload) => {
        const handler = this.commands.get(payload.command);
        if (handler) {
          const ctx = new CommandContext(this, payload);
          try {
            const result = handler(ctx);
            if (result instanceof Promise) {
              result.catch(() => {
                // Swallow — handler errors should not crash the SDK
              });
            }
          } catch {
            // Swallow
          }
        }
      });
    });

    return this.connectPromise;
  }

  disconnect(): void {
    if (this.socket) {
      this.socket.removeAllListeners();
      this.socket.disconnect();
      this.socket = null;
    }
    this.connectPromise = null;
  }

  // ---------------------------------------------------------------------------
  // Commands
  // ---------------------------------------------------------------------------

  /**
   * Register a command handler locally.
   *
   * When the server dispatches `command.invoked` for this command name, the
   * handler is called with a `CommandContext`.
   *
   * REST registration (`POST /api/v1/workspaces/:wid/bots/:bid/commands`) is
   * deferred — only the in-memory handler is stored for now.
   */
  command(name: string, handler: CommandHandler): void {
    this.commands.set(name, handler);
  }

  // ---------------------------------------------------------------------------
  // Events
  // ---------------------------------------------------------------------------

  /**
   * Listen for a server-sent socket event.
   *
   * If the socket is already connected the handler is attached immediately;
   * otherwise it is queued and attached once `connect()` is called.
   */
  on(event: string, handler: EventHandler): void {
    if (!this.eventHandlers.has(event)) {
      this.eventHandlers.set(event, new Set());
    }
    this.eventHandlers.get(event)!.add(handler);

    // If already connected, attach immediately (won't double-attach because
    // each handler instance is unique in the Set).
    if (this.socket) {
      this.socket.on(event, handler);
    }
  }

  // ---------------------------------------------------------------------------
  // Messaging
  // ---------------------------------------------------------------------------

  /**
   * Send a message to a channel.
   *
   * Emits `message.send` over the WebSocket. The server persists the message,
   * publishes it to the workspace, and replies with `message.confirmed` or
   * `message.failed`.
   */
  sendMessage(channelId: string, content: string, attachments?: string[]): Promise<void> {
    return new Promise<void>((resolve, reject) => {
      if (!this.socket?.connected) {
        reject(new Error('Bot is not connected'));
        return;
      }

      const payload: Record<string, unknown> = { channelId, content };
      if (attachments?.length) {
        payload.attachments = attachments;
      }

      this.socket.emit('message.send', payload);

      const onConfirmed = (_data: { messageId: string }) => {
        cleanup();
        resolve();
      };
      const onFailed = (data: { error: string }) => {
        cleanup();
        reject(new Error(data.error ?? 'Failed to send message'));
      };

      const cleanup = () => {
        this.socket?.off('message.confirmed', onConfirmed);
        this.socket?.off('message.failed', onFailed);
      };

      this.socket.once('message.confirmed', onConfirmed);
      this.socket.once('message.failed', onFailed);
    });
  }

  /**
   * Add a reaction to a message.
   *
   * Emits `reaction.add` over the WebSocket.
   */
  addReaction(channelId: string, messageId: string, emoji: string): void {
    if (!this.socket?.connected) {
      throw new Error('Bot is not connected');
    }

    this.socket.emit('reaction.add', { channelId, messageId, emoji });
  }

  // ---------------------------------------------------------------------------
  // Internal
  // ---------------------------------------------------------------------------

  /**
   * Attach all queued event handlers to the current socket.
   */
  private _attachEventHandlers(): void {
    if (!this.socket) return;
    for (const [event, handlers] of this.eventHandlers) {
      for (const handler of handlers) {
        this.socket.on(event, handler);
      }
    }
  }
}
