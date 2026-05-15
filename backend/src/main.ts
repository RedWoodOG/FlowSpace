import { NestFactory } from '@nestjs/core';
import { Logger, ValidationPipe } from '@nestjs/common';
import { AppModule } from './app.module';
import { RedisIoAdapter } from './adapters/redis-io.adapter';
import { json, urlencoded } from 'express';

async function bootstrap() {
  const logger = new Logger('Bootstrap');

  // Validate FRONTEND_URL — no wildcard fallback
  const frontendUrl = process.env.FRONTEND_URL;
  if (!frontendUrl) {
    if (process.env.NODE_ENV === 'production') {
      logger.error('FRONTEND_URL must be set in production');
      process.exit(1);
    }
  }
  // Only explicit origins allowed — platform wildcards removed (security risk)
  const origin = frontendUrl ? [frontendUrl] : ['http://localhost'];

  const app = await NestFactory.create(AppModule, {
    cors: {
      origin,
      credentials: true,
      methods: ['GET', 'POST', 'PUT', 'DELETE', 'PATCH', 'OPTIONS'],
      allowedHeaders: ['Content-Type', 'Authorization', 'X-Session-Token']
    }
  });

  // Security headers (Helmet)
  try {
    const helmet = require('helmet');
    app.use(helmet());
  } catch { /* helmet not installed yet; will be added via npm */ }

  // Body size limits
  app.use(json({ limit: '1mb' }));
  app.use(urlencoded({ limit: '1mb', extended: true }));

  // Global validation pipe — whitelist enabled
  app.useGlobalPipes(new ValidationPipe({
    whitelist: true,
    forbidNonWhitelisted: true,
    transform: true,
  }));

  app.setGlobalPrefix('api/v1', {
    exclude: ['assets/*']
  });

  // Redis adapter: fail-fast in production, graceful dev fallback only
  const redisUrl = process.env.REDIS_URL;
  if (redisUrl) {
    try {
      const redisIoAdapter = new RedisIoAdapter(app);
      await redisIoAdapter.connectToRedis();
      app.useWebSocketAdapter(redisIoAdapter);
      logger.log('Redis IO adapter connected');
    } catch (error) {
      logger.error('Failed to connect Redis adapter:', error);
      if (process.env.NODE_ENV === 'production') {
        logger.error('Redis is required in production — exiting');
        process.exit(1);
      }
      logger.warn('Continuing with in-memory Socket.IO adapter (dev only)');
    }
  } else if (process.env.NODE_ENV === 'production') {
    logger.error('REDIS_URL must be set in production');
    process.exit(1);
  } else {
    logger.warn('REDIS_URL not set — using in-memory Socket.IO adapter (dev only)');
  }

  const port = process.env.PORT || 4000;
  await app.listen(port, '0.0.0.0');

  logger.log(`🚀 FlowSpace backend running on port ${port}`);
  logger.log(`📡 API: http://localhost:${port}/api/v1`);
  logger.log(`🔌 WebSocket: ws://localhost:${port}`);
}

bootstrap();
