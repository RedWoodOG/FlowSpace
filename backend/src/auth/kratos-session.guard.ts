import {
  CanActivate,
  ExecutionContext,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import type { Request } from 'express';

import { KratosService } from './kratos.service';

interface KratosIdentityUser {
  id: string;
  email?: string;
  displayName?: string | null;
  identity: Record<string, any>;
  session: Record<string, any>;
}

@Injectable()
export class KratosSessionGuard implements CanActivate {
  constructor(private readonly kratos: KratosService) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const req = context
      .switchToHttp()
      .getRequest<Request & { user?: KratosIdentityUser }>();

    const cookie = req.headers.cookie;
    const sessionToken = req.headers['x-session-token'] as
      | string
      | undefined;

    const session = await this.kratos.whoAmI({
      cookie,
      sessionToken,
    });

    const identity = session.identity ?? {};
    if (!identity.id || typeof identity.id !== 'string') {
      throw new UnauthorizedException('Invalid identity');
    }
    const traits = (identity.traits ?? {}) as Record<string, any>;
    const email =
      traits['email'] ??
      traits['email_address'] ??
      traits['username'] ??
      identity.id;
    const displayName =
      traits['display_name'] ??
      traits['name'] ??
      traits['full_name'] ??
      email;

    req.user = {
      id: identity.id,
      email,
      displayName,
      identity,
      session,
    };

    return true;
  }
}

