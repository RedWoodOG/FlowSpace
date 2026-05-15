import {
  ConnectedSocket,
  MessageBody,
  SubscribeMessage,
  WebSocketGateway,
  WebSocketServer,
} from '@nestjs/websockets';
import { OnModuleInit, UnauthorizedException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { Server, Socket } from 'socket.io';

import { RedisService } from '../shared/redis.service';
import { AuthTokenPayload } from '../auth/jwt-payload.interface';
import {
  WorkspaceEvents,
  ChatMessagePayload,
  ChannelCreatedPayload,
} from '../../libs/shared';
import { ChatService } from './chat.service';
import { BotsService } from '../bots/bots.service';

@WebSocketGateway({ cors: true })
export class ChatGateway implements OnModuleInit {
  @WebSocketServer()
  server!: Server;

  constructor(
    private readonly redis: RedisService,
    private readonly config: ConfigService,
    private readonly jwtService: JwtService,
    private readonly chatService: ChatService,
    private readonly botsService: BotsService,
  ) {}

  async onModuleInit() {
    await this.redis.subscribe(
      [
        WorkspaceEvents.MESSAGE_SENT,
        WorkspaceEvents.CHANNEL_CREATED,
        'reaction.added',
        'reaction.removed',
        'message.edited',
        'message.deleted',
        'message.read',
        'mention.received',
      ],
      (channel: string, payload: string) => {
        const data = JSON.parse(payload);
        switch (channel) {
          case WorkspaceEvents.MESSAGE_SENT: {
            this.server.to(data.message.channelId).emit('message.new', {
              ...data.message,
              soundUrl: '/assets/sounds/notification.wav',
            });
            this.server
              .to(`workspace:${data.workspaceId}`)
              .emit('workspace.activity', { type: 'message', message: data.message });
            break;
          }
          case WorkspaceEvents.CHANNEL_CREATED: {
            this.server
              .to(`workspace:${data.workspaceId}`)
              .emit('channel.created', data);
            break;
          }
          case 'reaction.added':
          case 'reaction.removed':
            this.server.emit(channel, data);
            break;
          case 'message.edited':
            this.server.to(data.channelId).emit('message.edited', data);
            break;
          case 'message.deleted':
            this.server.to(data.channelId).emit('message.deleted', data);
            break;
          case 'message.read':
            this.server.emit('message.read', data);
            break;
          case 'mention.received':
            this.server.to(data.channelId).emit('mention.received', {
              ...data,
              soundUrl: '/assets/sounds/clockbeep.mp3',
            });
            break;
          default:
            break;
        }
      },
    );
  }

  async handleConnection(client: Socket) {
    // TEMPORARY: Allow connections without JWT token for testing
    try {
      const payload = await this.extractUser(client);
      client.data.user = payload;
      console.log(`[ChatGateway] Client connected with JWT: ${payload.email}`);
    } catch (error) {
      // Allow connection without JWT for testing
      console.log(`[ChatGateway] Client connected without valid JWT (testing mode)`);
      client.data.user = {
        id: 'anonymous',
        email: 'test@flowspace.local',
        displayName: 'Test User',
      };
    }

    const workspaceId = client.handshake.query.workspaceId as string | undefined;
    const channelId = client.handshake.query.channelId as string | undefined;

    if (!workspaceId) {
      client.disconnect(true);
      return;
    }

    console.log(`[ChatGateway] Client joined workspace: ${workspaceId}${channelId ? `, channel: ${channelId}` : ''}`);
    client.join(`workspace:${workspaceId}`);

    if (channelId) {
      client.join(channelId);
    }
  }

  @SubscribeMessage('channel.join')
  handleJoin(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: { channelId: string },
  ) {
    client.join(data.channelId);
  }

  @SubscribeMessage('channel.leave')
  handleLeave(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: { channelId: string },
  ) {
    client.leave(data.channelId);
  }

  @SubscribeMessage('message.send')
  async handleMessageSend(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: {
      tempId: string;
      channelId: string;
      content: string;
      attachments?: string[];
      threadId?: string;
    },
  ) {
    const workspaceId = client.handshake.query.workspaceId as string | undefined;
    const user = client.data.user as
      | {
          id: string;
          email: string;
          displayName: string;
        }
      | undefined;

    if (!workspaceId || !user) {
      client.emit('message.failed', {
        tempId: data.tempId,
        error: 'Missing workspace or user context',
      });
      return;
    }

    // ---- BOT COMMAND ROUTING ----
    if (data.content.startsWith('/')) {
      const commandEntry = await this.botsService.findCommandInWorkspace(workspaceId, data.content);
      if (commandEntry) {
        const args = data.content.substring(commandEntry.command.length).trim();
        const commandPayload = {
          command: commandEntry.command,
          args,
          channelId: data.channelId,
          userId: user.id,
          userName: user.displayName,
          messageId: data.tempId,
          timestamp: new Date().toISOString(),
        };

        if (commandEntry.handlerType === 'WEBSOCKET') {
          // Dispatch to connected bot via BotsGateway
          const { BotsGateway } = require('../bots/bots.gateway');
          // The gateway instance is managed by NestJS - we publish via Redis for decoupling
          await this.redis.publish('command.invoked', {
            workspaceId,
            botId: commandEntry.botId,
            ...commandPayload,
          });
          client.emit('message.sent', {
            tempId: data.tempId,
            messageId: `cmd_${Date.now()}`,
            timestamp: Date.now(),
          });
          return;
        } else if (commandEntry.handlerType === 'WEBHOOK' && commandEntry.handlerUrl) {
          // Fire-and-forget webhook call
          try {
            const https = require('https');
            const { URL } = require('url');
            const webhookUrl = new URL(commandEntry.handlerUrl);
            const postData = JSON.stringify(commandPayload);
            const req = https.request({
              hostname: webhookUrl.hostname,
              port: webhookUrl.port || 443,
              path: webhookUrl.pathname + webhookUrl.search,
              method: 'POST',
              headers: {
                'Content-Type': 'application/json',
                'Content-Length': Buffer.byteLength(postData),
              },
            });
            req.write(postData);
            req.end();
          } catch (webhookError) {
            console.error('[ChatGateway] Webhook dispatch failed:', webhookError);
          }
          client.emit('message.sent', {
            tempId: data.tempId,
            messageId: `cmd_${Date.now()}`,
            timestamp: Date.now(),
          });
          return;
        }
      }
    }

    try {
      // Call chat service to persist message
      const result = await this.chatService.sendMessage({
        workspaceId,
        channelId: data.channelId,
        senderId: user.id,
        content: data.content,
        attachments: data.attachments,
        parentId: data.threadId,
      });

      // Send success acknowledgment back to sender
      client.emit('message.sent', {
        tempId: data.tempId,
        messageId: result.message.id,
        timestamp: new Date(result.message.timestamp).getTime(),
      });

      console.log(`[ChatGateway] Message sent: ${data.tempId} -> ${result.message.id}`);
    } catch (error) {
      console.error('[ChatGateway] Error sending message:', error);
      
      // Send failure acknowledgment
      client.emit('message.failed', {
        tempId: data.tempId,
        error: error instanceof Error ? error.message : 'Failed to send message',
      });
    }
  }

  @SubscribeMessage('message.edit')
  async handleMessageEdit(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: {
      messageId: string;
      content: string;
    },
  ) {
    // Will be implemented in future steps
    console.log('[ChatGateway] Message edit requested:', data.messageId);
  }

  @SubscribeMessage('message.delete')
  async handleMessageDelete(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: {
      messageId: string;
    },
  ) {
    // Will be implemented in future steps
    console.log('[ChatGateway] Message delete requested:', data.messageId);
  }

  @SubscribeMessage('message.read')
  async handleMessageRead(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: {
      messageId: string;
      timestamp: number;
    },
  ) {
    const user = client.data.user as
      | {
          id: string;
          email: string;
          displayName: string;
        }
      | undefined;

    if (!user) return;

    // Broadcast read receipt to all users in the channel
    const channelId = client.handshake.query.channelId as string | undefined;
    if (channelId) {
      await this.redis.publish('message.read', {
        channelId,
        messageId: data.messageId,
        userId: user.id,
        displayName: user.displayName,
        timestamp: data.timestamp,
      });
    }
  }

  // ===== REACTIONS =====
  @SubscribeMessage('reaction.add')
  async handleReactionAdd(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: {
      channelId: string;
      messageId: string;
      emoji: string;
    },
  ) {
    const user = client.data.user as { id: string; displayName: string } | undefined;
    if (!user) return;

    const event = {
      messageId: data.messageId,
      channelId: data.channelId,
      userId: user.id,
      displayName: user.displayName,
      emoji: data.emoji,
      action: 'add',
      timestamp: new Date().toISOString(),
    };

    await this.redis.publish('reaction.added', event);
    console.log(`[ChatGateway] Reaction added: ${data.emoji} on ${data.messageId}`);
  }

  @SubscribeMessage('reaction.remove')
  async handleReactionRemove(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: {
      channelId: string;
      messageId: string;
      emoji: string;
    },
  ) {
    const user = client.data.user as { id: string; displayName: string } | undefined;
    if (!user) return;

    const event = {
      messageId: data.messageId,
      channelId: data.channelId,
      userId: user.id,
      displayName: user.displayName,
      emoji: data.emoji,
      action: 'remove',
      timestamp: new Date().toISOString(),
    };

    await this.redis.publish('reaction.removed', event);
    console.log(`[ChatGateway] Reaction removed: ${data.emoji} from ${data.messageId}`);
  }

  // ===== MESSAGE PINNING =====
  @SubscribeMessage('message.pin')
  async handleMessagePin(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: {
      channelId: string;
      messageId: string;
      reason?: string;
    },
  ) {
    const user = client.data.user as { id: string; displayName: string } | undefined;
    if (!user) return;

    const event = {
      messageId: data.messageId,
      channelId: data.channelId,
      action: 'pin',
      pinnedMessage: {
        messageId: data.messageId,
        channelId: data.channelId,
        content: 'Message content here',
        authorId: 'authorId',
        authorName: 'Author Name',
        messageTimestamp: new Date().toISOString(),
        pinnedAt: new Date().toISOString(),
        pinnedBy: user.id,
        pinnedByName: user.displayName,
        pinnedReason: data.reason,
      },
      timestamp: new Date().toISOString(),
    };

    this.server.to(data.channelId).emit('message.pinned', event);
    console.log(`[ChatGateway] Message pinned: ${data.messageId}`);
  }

  @SubscribeMessage('message.unpin')
  async handleMessageUnpin(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: {
      channelId: string;
      messageId: string;
    },
  ) {
    const event = {
      messageId: data.messageId,
      channelId: data.channelId,
      action: 'unpin',
      timestamp: new Date().toISOString(),
    };

    this.server.to(data.channelId).emit('message.unpinned', event);
    console.log(`[ChatGateway] Message unpinned: ${data.messageId}`);
  }

  // ===== BULLETINS =====
  @SubscribeMessage('bulletin.create')
  async handleBulletinCreate(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: any,
  ) {
    const user = client.data.user as { id: string; displayName: string } | undefined;
    if (!user) return;

    const bulletin = {
      id: `bulletin_${Date.now()}`,
      workspaceId: data.workspaceId,
      title: data.title,
      content: data.content,
      authorId: user.id,
      authorName: user.displayName,
      createdAt: new Date().toISOString(),
      priority: data.priority || 'normal',
      type: data.type || 'announcement',
      expiresAt: data.expiresAt,
      tags: data.tags || [],
      isPinned: false,
      viewCount: 0,
      attachmentUrls: data.attachmentUrls || [],
    };

    const event = {
      bulletinId: bulletin.id,
      workspaceId: data.workspaceId,
      action: 'created',
      bulletin,
      timestamp: new Date().toISOString(),
    };

    this.server.to(`workspace:${data.workspaceId}`).emit('bulletin.created', event);
    console.log(`[ChatGateway] Bulletin created: ${bulletin.id}`);
  }

  @SubscribeMessage('bulletin.update')
  async handleBulletinUpdate(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: any,
  ) {
    const event = {
      bulletinId: data.id,
      workspaceId: data.workspaceId,
      action: 'updated',
      bulletin: {
        ...data,
        updatedAt: new Date().toISOString(),
      },
      timestamp: new Date().toISOString(),
    };

    this.server.to(`workspace:${data.workspaceId}`).emit('bulletin.updated', event);
    console.log(`[ChatGateway] Bulletin updated: ${data.id}`);
  }

  @SubscribeMessage('bulletin.delete')
  async handleBulletinDelete(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: {
      workspaceId: string;
      bulletinId: string;
    },
  ) {
    const event = {
      bulletinId: data.bulletinId,
      workspaceId: data.workspaceId,
      action: 'deleted',
      timestamp: new Date().toISOString(),
    };

    this.server.to(`workspace:${data.workspaceId}`).emit('bulletin.deleted', event);
    console.log(`[ChatGateway] Bulletin deleted: ${data.bulletinId}`);
  }

  @SubscribeMessage('bulletin.pin')
  async handleBulletinPin(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: {
      workspaceId: string;
      bulletinId: string;
    },
  ) {
    const event = {
      bulletinId: data.bulletinId,
      workspaceId: data.workspaceId,
      action: 'pinned',
      bulletin: null,
      timestamp: new Date().toISOString(),
    };

    this.server.to(`workspace:${data.workspaceId}`).emit('bulletin.pinned', event);
    console.log(`[ChatGateway] Bulletin pinned: ${data.bulletinId}`);
  }

  @SubscribeMessage('bulletin.unpin')
  async handleBulletinUnpin(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: {
      workspaceId: string;
      bulletinId: string;
    },
  ) {
    const event = {
      bulletinId: data.bulletinId,
      workspaceId: data.workspaceId,
      action: 'unpinned',
      bulletin: null,
      timestamp: new Date().toISOString(),
    };

    this.server.to(`workspace:${data.workspaceId}`).emit('bulletin.unpinned', event);
    console.log(`[ChatGateway] Bulletin unpinned: ${data.bulletinId}`);
  }

  private async extractUser(
    client: Socket,
  ): Promise<{
    id: string;
    email: string;
    displayName: string;
    identity: Record<string, any>;
    session: Record<string, any>;
  }> {
    let token: string | undefined =
      (client.handshake.auth?.token as string | undefined) ??
      (client.handshake.query.token as string | undefined);

    if (!token) {
      const authHeader = client.handshake.headers?.authorization as string | undefined;
      if (authHeader && authHeader.startsWith('Bearer ')) {
        token = authHeader.substring(7);
      }
    }

    if (!token) {
      throw new UnauthorizedException('Missing JWT token');
    }

    const jwtSecret = this.config.get<string>('JWT_SECRET');
    if (!jwtSecret) {
      throw new Error('JWT_SECRET is not configured');
    }

    let payload: AuthTokenPayload;
    try {
      payload = this.jwtService.verify(token, {
        secret: jwtSecret,
      }) as AuthTokenPayload;
    } catch (error) {
      throw new UnauthorizedException('Invalid or expired JWT token');
    }

    const userId = payload.sub;
    const email = payload.email;
    const displayName = payload.displayName ?? email;

    if (!userId || !email) {
      throw new UnauthorizedException('Invalid JWT payload');
    }

    return {
      id: userId,
      email,
      displayName,
      identity: {
        id: userId,
        email,
        displayName,
      },
      session: {
        id: userId,
        email,
      },
    };
  }
}
