import { IoAdapter } from '@nestjs/platform-socket.io';
import { Logger } from '@nestjs/common';
import { ServerOptions } from 'socket.io';
import { createAdapter } from '@socket.io/redis-adapter';
import { createClient } from 'redis';

export class RedisIoAdapter extends IoAdapter {
  private readonly logger = new Logger(RedisIoAdapter.name);
  private adapterConstructor?: ReturnType<typeof createAdapter>;

  async connectToRedis(): Promise<void> {
    const redisUrl = process.env.REDIS_URL;
    
    if (!redisUrl) {
      if (process.env.NODE_ENV === 'production') {
        throw new Error('REDIS_URL is required in production for multi-instance Socket.IO');
      }
      this.logger.warn('REDIS_URL not set — using in-memory adapter (single instance only)');
      return;
    }

    this.logger.log('Connecting to Redis for Socket.IO...');
    
    const pubClient = createClient({ url: redisUrl });
    const subClient = pubClient.duplicate();

    pubClient.on('error', (err) => { this.logger.error('Redis pubClient error:', err.message); });
    subClient.on('error', (err) => { this.logger.error('Redis subClient error:', err.message); });

    await Promise.all([pubClient.connect(), subClient.connect()]);

    this.adapterConstructor = createAdapter(pubClient, subClient);
    this.logger.log('Redis adapter connected');
  }

  createIOServer(port: number, options?: ServerOptions): any {
    const server = super.createIOServer(port, options);
    
    if (this.adapterConstructor) {
      server.adapter(this.adapterConstructor);
      this.logger.log('Socket.IO using Redis adapter');
    } else {
      this.logger.log('Socket.IO using in-memory adapter');
    }
    
    return server;
  }
}
