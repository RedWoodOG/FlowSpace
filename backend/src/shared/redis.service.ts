import { Injectable, Logger, OnModuleDestroy } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import Redis from 'ioredis';

@Injectable()
export class RedisService implements OnModuleDestroy {
  private readonly logger = new Logger(RedisService.name);
  private readonly publisher: Redis;
  private readonly subscriber: Redis;

  constructor(private readonly configService: ConfigService) {
    const url =
      this.configService.get<string>('REDIS_URL') ?? 'redis://localhost:6379';

    this.publisher = new Redis(url, {
      retryStrategy: (times) => {
        const delay = Math.min(times * 50, 2000);
        return delay;
      },
      maxRetriesPerRequest: null,
      enableReadyCheck: false,
      lazyConnect: true,
      showFriendlyErrorStack: false,
    });
    
    this.subscriber = new Redis(url, {
      retryStrategy: (times) => {
        const delay = Math.min(times * 50, 2000);
        return delay;
      },
      maxRetriesPerRequest: null,
      enableReadyCheck: false,
      lazyConnect: true,
      showFriendlyErrorStack: false,
    });
    
    this.publisher.on('error', (error: any) => {
      this.logger.error('Redis publisher error:', error?.message || error);
    });
    
    this.subscriber.on('error', (error: any) => {
      this.logger.error('Redis subscriber error:', error?.message || error);
    });
    
    this.publisher.connect().catch(err => {
      this.logger.error('Redis publisher failed to connect:', err.message);
    });
    this.subscriber.connect().catch(err => {
      this.logger.error('Redis subscriber failed to connect:', err.message);
    });
  }

  getPublisher(): Redis {
    return this.publisher;
  }

  getSubscriber(): Redis {
    return this.subscriber;
  }

  isHealthy(): boolean {
    return this.publisher.status === 'ready' && this.subscriber.status === 'ready';
  }

  async publish(channel: string, payload: unknown): Promise<number> {
    try {
      const message =
        typeof payload === 'string' ? payload : JSON.stringify(payload);
      
      if (this.publisher.status !== 'ready') {
        await this.publisher.connect().catch(() => {
          return 0;
        });
      }
      
      if (this.publisher.status === 'ready') {
        return await this.publisher.publish(channel, message);
      }
      return 0;
    } catch (error: any) {
      this.logger.error('Redis publish failed:', error?.message || error);
      return 0;
    }
  }

  async publishRequired(channel: string, payload: unknown): Promise<number> {
    const message =
      typeof payload === 'string' ? payload : JSON.stringify(payload);
    return this.publisher.publish(channel, message);
  }

  async subscribe(
    channels: string[],
    handler: (channel: string, payload: string) => void,
  ): Promise<void> {
    if (channels.length === 0) {
      return;
    }

    try {
      if (this.subscriber.status !== 'ready') {
        await this.subscriber.connect().catch(() => {
          return;
        });
      }
      
      if (this.subscriber.status === 'ready') {
        await this.subscriber.subscribe(...channels);
        this.subscriber.on('message', handler);
      }
    } catch (error: any) {
      this.logger.error('Redis subscribe failed:', error?.message || error);
    }
  }

  async onModuleDestroy(): Promise<void> {
    await Promise.all([this.publisher.quit(), this.subscriber.quit()]);
  }
}
