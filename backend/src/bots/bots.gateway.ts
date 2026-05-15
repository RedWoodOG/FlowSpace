import {
  ConnectedSocket,
  MessageBody,
  SubscribeMessage,
  WebSocketGateway,
  WebSocketServer,
  OnGatewayConnection,
  OnGatewayDisconnect,
} from '@nestjs/websockets';
import { Logger, OnModuleInit } from '@nestjs/common';
import { Server, Socket } from 'socket.io';
import { BotsService } from './bots.service';
import { RedisService } from '../shared/redis.service';
import { WorkspaceEvents } from '../../libs/shared';

@WebSocketGateway({ cors: true })
export class BotsGateway implements OnGatewayConnection, OnGatewayDisconnect, OnModuleInit {
  @WebSocketServer()
  server!: Server;

  private readonly logger = new Logger(BotsGateway.name);
  private readonly connectedBots = new Map<string, { botId: string; workspaceId: string; socket: Socket }>();

  private readonly botRateLimit = new Map<string, { count: number; resetAt: number }>();
  private readonly RATE_LIMIT_WINDOW = 1000;
  private readonly RATE_LIMIT_MAX = 10;

  constructor(
    private readonly botsService: BotsService,
    private readonly redis: RedisService,
  ) {}

  async onModuleInit() {
    await this.redis.subscribe(['command.invoked'], (channel: string, payload: string) => {
      if (channel === 'command.invoked') {
        const data = JSON.parse(payload);
        this.dispatchCommandToBot(data.workspaceId, data.botId, 'command.invoked', data);
      }
    });
  }

  async handleConnection(client: Socket) {
    const apiKey = client.handshake.auth?.token as string | undefined;
    if (!apiKey || !apiKey.startsWith('flo_')) {
      // Not a bot connection — let ChatGateway handle it
      return;
    }

    const botContext = await this.botsService.validateApiKey(apiKey);
    if (!botContext) {
      this.logger.warn(`Bot connection rejected: invalid API key`);
      client.emit('error', { message: 'Invalid API key' });
      client.disconnect(true);
      return;
    }

    const bot = await this.botsService.getBotForConnection(
      botContext.workspaceId,
      botContext.botId,
    );

    if (!bot) {
      this.logger.warn(`Bot connection rejected: bot not found`);
      client.disconnect(true);
      return;
    }

    client.data.bot = {
      id: botContext.id,
      botId: botContext.botId,
      workspaceId: botContext.workspaceId,
      name: bot.name,
    };

    const key = `${botContext.workspaceId}:${botContext.botId}`;
    this.connectedBots.set(key, { botId: botContext.botId, workspaceId: botContext.workspaceId, socket: client });

    // Join workspace room
    client.join(`workspace:${botContext.workspaceId}`);

    // Subscribe to bot's registered events via Redis
    const events = await this.botsService.getBotSubscribedEvents(botContext.botId);
    for (const event of events) {
      client.join(`bot:${botContext.botId}:${event}`);
    }

    this.logger.log(`Bot connected: ${bot.name} (${botContext.workspaceId})`);
    client.emit('connected', { botId: botContext.botId, workspaceId: botContext.workspaceId });
  }

  async handleDisconnect(client: Socket) {
    const bot = client.data.bot;
    if (bot) {
      const key = `${bot.workspaceId}:${bot.botId}`;
      this.connectedBots.delete(key);
      this.logger.log(`Bot disconnected: ${bot.name}`);
    }
  }

  @SubscribeMessage('message.send')
  async handleBotMessage(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: {
      channelId: string;
      content: string;
      attachments?: string[];
      threadId?: string;
    },
  ) {
    const bot = client.data.bot;
    if (!bot) return;

    // Per-bot rate limiting: sliding window, 10 messages/second
    const now = Date.now();
    const rl = this.botRateLimit.get(bot.botId);
    if (rl && now < rl.resetAt) {
      if (rl.count >= this.RATE_LIMIT_MAX) {
        client.emit('message.failed', { error: 'Rate limit exceeded' });
        return;
      }
      rl.count++;
    } else {
      this.botRateLimit.set(bot.botId, { count: 1, resetAt: now + this.RATE_LIMIT_WINDOW });
    }

    try {
      // Persist bot message via service (includes channel-to-workspace validation)
      const message = await this.botsService.persistBotMessage(
        bot.botId,
        data.channelId,
        data.content,
        data.attachments,
        data.threadId,
      );

      // Publish to workspace for all clients
      const payload = {
        id: message.id,
        channelId: message.channelId,
        senderId: `bot:${bot.botId}`,
        senderName: `🤖 ${bot.name}`,
        content: message.content,
        attachments: message.attachments,
        parentId: message.parentId || null,
        timestamp: message.createdAt.toISOString(),
        isBot: true,
        botId: bot.botId,
      };

      await this.redis.publish(WorkspaceEvents.MESSAGE_SENT, {
        workspaceId: bot.workspaceId,
        message: payload,
      });

      client.emit('message.confirmed', { messageId: message.id });
    } catch (error) {
      this.logger.error(`Bot message send failed:`, error);
      client.emit('message.failed', { error: 'Failed to send message' });
    }
  }

  @SubscribeMessage('reaction.add')
  async handleBotReaction(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: {
      channelId: string;
      messageId: string;
      emoji: string;
    },
  ) {
    const bot = client.data.bot;
    if (!bot) return;

    await this.redis.publish('reaction.added', {
      messageId: data.messageId,
      channelId: data.channelId,
      userId: `bot:${bot.botId}`,
      displayName: `🤖 ${bot.name}`,
      emoji: data.emoji,
      action: 'add',
      timestamp: new Date().toISOString(),
    });
  }

  @SubscribeMessage('typing')
  async handleBotTyping(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: { channelId: string },
  ) {
    const bot = client.data.bot;
    if (!bot) return;

    this.server.to(data.channelId).emit('typing', {
      channelId: data.channelId,
      userId: `bot:${bot.botId}`,
      userName: `🤖 ${bot.name}`,
    });
  }

  isBotConnected(botId: string, workspaceId: string): boolean {
    return this.connectedBots.has(`${workspaceId}:${botId}`);
  }

  dispatchCommandToBot(workspaceId: string, botId: string, event: string, payload: any) {
    const key = `${workspaceId}:${botId}`;
    const entry = this.connectedBots.get(key);
    if (entry) {
      entry.socket.emit(event, payload);
      return true;
    }
    return false;
  }
}
