# Target
Fix main.ts and app.module.ts for security infrastructure

# Changes (apply EVERY one):

## main.ts
1. Import `helmet` from 'helmet' (install it — but DON'T run npm install, just add the import; we'll install later). Add `app.use(helmet())` after app creation. Use a try/catch around it in case helmet isn't installed yet: wrap in `try { const helmet = require('helmet'); app.use(helmet()); } catch {}`.
2. Fix CORS: Remove `'*'` fallback. Remove `process.env.FRONTEND_URL || '*'`. Change to: read `FRONTEND_URL` from env, if missing in production throw error, if missing in dev default to `['http://localhost']`. Remove `https://*.onrender.com` and `https://*.railway.app` — replace with explicit URLs if needed. Add comment that platform wildcards are a security risk.
   ```typescript
   const frontendUrl = process.env.FRONTEND_URL;
   if (!frontendUrl) {
     if (process.env.NODE_ENV === 'production') {
       logger.error('FRONTEND_URL must be set in production');
       process.exit(1);
     }
   }
   const origin = frontendUrl ? [frontendUrl] : ['http://localhost'];
   ```
3. Add explicit body size limits: right after app creation, add:
   ```typescript
   import { json, urlencoded } from 'express';
   app.use(json({ limit: '1mb' }));
   app.use(urlencoded({ limit: '1mb', extended: true }));
   ```
4. Enable ValidationPipe globally: `app.useGlobalPipes(new ValidationPipe({ whitelist: true, forbidNonWhitelisted: true, transform: true }))`. Import `ValidationPipe` from '@nestjs/common'.
5. Remove the try/catch Redis fallback in bootstrap that silently degrades. Instead: if REDIS_URL is set, use Redis adapter. If adapter fails to connect, log error AND exit if in production. If REDIS_URL is NOT set and NODE_ENV is production, log error and exit. Only continue without Redis in development.

## app.module.ts
1. Add `ThrottlerModule` import. Import `ThrottlerModule` from '@nestjs/throttler'. Add to imports: `ThrottlerModule.forRoot([{ ttl: 60000, limit: 100 }])`. Use try/catch pattern in case package isn't installed:
   ```
   // ThrottlerModule.forRoot is added conditionally
   // We use a dynamic import pattern - but for NestJS modules, we need to add it statically
   ```
   Actually, just add the import and module registration. We'll install the package.

## kratos-session.guard.ts
1. Add validation that `identity.id` is a non-empty string. After destructuring `identity`, check: `if (!identity.id || typeof identity.id !== 'string') { throw new UnauthorizedException('Invalid identity'); }`
