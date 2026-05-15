import {
  ConnectedSocket,
  MessageBody,
  SubscribeMessage,
  WebSocketGateway,
  WebSocketServer,
} from '@nestjs/websockets';
import {
  BadRequestException,
  OnModuleInit,
  UnauthorizedException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { Server, Socket } from 'socket.io';

import { RedisService } from '../shared/redis.service';
import { AuthTokenPayload } from '../auth/jwt-payload.interface';
import { WorkspaceEvents } from '../../libs/shared';

interface PresenceMessage {
  workspaceId: string;
  userId: string;
  status: 'online' | 'offline' | 'away';
  lastActiveAt: string;
}

@WebSocketGateway({ cors: true, namespace: 'presence' })
export class PresenceGateway implements OnModuleInit {
  private static readonly TTL_SECONDS = 30;

  private readonly lastHeartbeat = new Map<string, number>();

  @WebSocketServer()
  server!: Server;

  constructor(
    private readonly redis: RedisService,
    private readonly config: ConfigService,
    private readonly jwtService: JwtService,
  ) {}

  async onModuleInit() {
    await this.redis.subscribe(
      [WorkspaceEvents.PRESENCE_UPDATE],
      (channel: string, payload: string) => {
        if (channel !== WorkspaceEvents.PRESENCE_UPDATE) {
          return;
        }

        const message = JSON.parse(payload) as PresenceMessage;
        this.server
          .to(`workspace:${message.workspaceId}`)
          .emit('presence.update', message);
      },
    );
  }

  async handleConnection(client: Socket) {
    let user:
      | {
          id: string;
          email: string;
          displayName: string;
          identity: Record<string, any>;
          session: Record<string, any>;
        }
      | undefined;
    try {
      user = await this.extractUser(client);
    } catch (error) {
      client.disconnect(true);
      return;
    }

    client.data.user = user;

    const workspaceId = client.handshake.query.workspaceId as string | undefined;
    if (!workspaceId) {
      client.disconnect(true);
      return;
    }

    client.join(`workspace:${workspaceId}`);
    void this.setStatus(workspaceId, user.id, 'online', user.displayName);
    
    // Broadcast user joined to workspace
    this.server.to(`workspace:${workspaceId}`).emit('user_joined', {
      userId: user.id,
      displayName: user.displayName,
      email: user.email,
      soundUrl: '/assets/sounds/whoosh.mp3',
    });
  }

  handleDisconnect(client: Socket) {
    const workspaceId = client.handshake.query.workspaceId as string | undefined;
    const user = client.data.user as
      | {
          id: string;
          email: string;
          displayName: string;
        }
      | undefined;

    if (!workspaceId || !user) {
      return;
    }

    void this.setStatus(workspaceId, user.id, 'offline');
    
    // Broadcast user left to workspace
    this.server.to(`workspace:${workspaceId}`).emit('user_left', {
      userId: user.id,
      displayName: user.displayName,
      soundUrl: '/assets/sounds/whoosh.mp3',
    });
  }

  @SubscribeMessage('channel.join')
  handleChannelJoin(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: { channelId: string },
  ) {
    client.join(data.channelId);
  }

  @SubscribeMessage('channel.leave')
  handleChannelLeave(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: { channelId: string },
  ) {
    client.leave(data.channelId);
  }

  @SubscribeMessage('heartbeat')
  async handleHeartbeat(
    @ConnectedSocket() client: Socket,
    @MessageBody()
    data: {
      status?: 'online' | 'offline' | 'away';
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
      throw new BadRequestException('workspaceId and token are required');
    }

    const key = `${workspaceId}:${user.id}`;
    const now = Date.now();
    const last = this.lastHeartbeat.get(key);
    if (last && now - last < 15000) {
      return;
    }
    this.lastHeartbeat.set(key, now);

    await this.setStatus(workspaceId, user.id, data.status ?? 'online', user.displayName);
  }

  @SubscribeMessage('typing')
  handleTyping(
    @ConnectedSocket() client: Socket,
    @MessageBody() body: { channelId: string; typing: boolean },
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
      return;
    }

    this.server
      .to(body.channelId)
      .emit('typing', {
        userId: user.id,
        typing: body.typing,
        channelId: body.channelId,
        displayName: user.displayName,
        timestamp: Date.now(),
      });
  }

  private async setStatus(
    workspaceId: string,
    userId: string,
    status: 'online' | 'offline' | 'away',
    displayName?: string,
  ) {
    const key = `presence:${workspaceId}:${userId}`;
    const publisher = this.redis.getPublisher();

    // Store both status and displayName
    const userData = JSON.stringify({ status, displayName });
    await publisher.set(key, userData, 'EX', PresenceGateway.TTL_SECONDS);

    const payload: PresenceMessage & { displayName?: string } = {
      workspaceId,
      userId,
      status,
      displayName,
      lastActiveAt: new Date().toISOString(),
    };

    await this.redis.publish(WorkspaceEvents.PRESENCE_UPDATE, payload);
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
    // Extract JWT token from auth object or Authorization header
    let token: string | undefined =
      (client.handshake.auth?.token as string | undefined) ??
      (client.handshake.query.token as string | undefined);

    // If not in auth/query, try Authorization header (Bearer token)
    if (!token) {
      const authHeader = client.handshake.headers?.authorization as
        | string
        | undefined;
      if (authHeader && authHeader.startsWith('Bearer ')) {
        token = authHeader.substring(7);
      }
    }

    if (!token) {
      throw new UnauthorizedException('Missing JWT token');
    }

    // Verify JWT token using JwtService
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

    // Extract user information from JWT payload
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