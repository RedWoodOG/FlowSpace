import {
  CanActivate,
  ExecutionContext,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import { Request } from 'express';

import { AuthService } from './auth.service';
import { AuthTokenPayload } from './jwt-payload.interface';

@Injectable()
export class JwtAuthGuard implements CanActivate {
  constructor(private readonly authService: AuthService) {}

  canActivate(context: ExecutionContext): boolean {
    if (context.getType() !== 'http') {
      throw new UnauthorizedException('JWT guard only supports HTTP contexts');
    }

    const request = context.switchToHttp().getRequest<Request & { user?: AuthTokenPayload }>();
    const authHeader = request.headers.authorization;

    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      throw new UnauthorizedException('Missing authorization token');
    }

    const token = authHeader.slice('Bearer '.length);
    const payload = this.authService.verifyToken(token);
    
    // Map JWT payload to user object expected by controllers
    request.user = {
      id: payload.sub,
      email: payload.email,
      displayName: payload.displayName,
    } as any;
    
    return true;
  }
}