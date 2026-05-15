# Target
Fix auth.service.ts, auth.controller.ts, jwt.guard.ts, jwt-payload.interface.ts, token.service.ts, bots-auth.guard.ts

# Changes (apply EVERY one):

## auth.service.ts
1. Change ALL `hash(password, 8)` and `hash(rawKey, 8)` to `hash(password, 12)` — everywhere bcrypt hash is called
2. In `issueToken()`: add `algorithm: 'HS256' as const` to sign options: `sign(payload, this.jwtSecret, { expiresIn: this.tokenTtl, algorithm: 'HS256' })`
3. In `verifyToken()`: add `algorithms: ['HS256']` to verify options: `verify(token, this.jwtSecret, { algorithms: ['HS256'] })`
4. In `registerWithVerification()`: change the `ConflictException` for existing user to return same message as success so email enumeration is prevented. Instead of throwing ConflictException, return `{ message: 'If this email is eligible, a verification message will be sent.', userId: 'pending' }` — but DON'T actually create a duplicate user. Just return the uniform message and return early.

## auth.controller.ts
1. Add proper DTO classes at top of file using class-validator decorators. Create:
   - `RegisterDto` with `@IsEmail() email`, `@MinLength(8) password`, `@IsString() @MinLength(1) name`, `@IsOptional() @IsString() nickname`
   - `LoginDto` with `@IsEmail() email`, `@IsString() password`
   - `RefreshDto` with `@IsString() refreshToken`
   - `LogoutDto` with `@IsOptional() @IsString() refreshToken`
2. Replace all `@Body() body: { email?: string; ... }` with typed DTOs
3. In `logout()`: after `JwtAuthGuard` authenticates, verify that the refresh token belongs to the authenticated user. Add `import { Request } from 'express'` and use `@Req() req: Request & { user?: { id: string } }`. Before calling `revokeRefreshToken`, look up the token and check ownership.
4. Keep validation guard checks for login/register as belt-and-suspenders (check email/password/name exist)

## jwt.guard.ts
1. Change non-HTTP branch from `return true` to `throw new UnauthorizedException('JWT guard only supports HTTP contexts')`
2. Import `Request` from express properly (it's already imported)

## token.service.ts
1. In `saveRefreshToken()`: bcrypt-hash the token before storing. Import `hash from 'bcrypt'`. Add `const tokenHash = await hash(token, 12)`. Store `tokenHash` instead of raw `token`.
2. In `validateRefreshToken()`: change lookup from `where: { token }` to iterate. Actually, simpler approach: store a lookup key (first 10 chars of raw token) alongside the hash. Add a `lookupKey` field or change strategy. EASIEST APPROACH: Store the raw token AND the hash. Store `token` in a `lookupKey` field (first 16 chars) and `tokenHash` as bcrypt hash. Then validate by: look up by lookupKey, bcrypt compare the raw token against stored hash.
3. Update the RefreshToken model in Prisma schema to add `lookupKey` field if needed — we'll handle schema separately. For now, store the bcrypt hash in the `token` field (rename to tokenHash in code, keep column name 'token' in DB — don't change schema in this pass).

## bots-auth.guard.ts
1. Change non-HTTP/non-WebSocket branch from `return true` (line ~34-36) to `throw new UnauthorizedException('BotAuthGuard only supports HTTP and WebSocket contexts')`
