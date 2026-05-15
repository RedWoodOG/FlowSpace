import {
  Injectable,
  CanActivate,
  ExecutionContext,
  UnauthorizedException,
} from '@nestjs/common';
import { BotsService } from './bots.service';

@Injectable()
export class BotAuthGuard implements CanActivate {
  constructor(private readonly botsService: BotsService) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const type = context.getType();

    if (type === 'http') {
      const request = context.switchToHttp().getRequest();
      const authHeader = request.headers.authorization;

      if (!authHeader || !authHeader.startsWith('Bot ')) {
        throw new UnauthorizedException('Missing bot authorization token');
      }

      const apiKey = authHeader.slice('Bot '.length);
      const botContext = await this.botsService.validateApiKey(apiKey);

      if (!botContext) {
        throw new UnauthorizedException('Invalid bot API key');
      }

      (request as any).bot = {
        id: botContext.id,
        botId: botContext.botId,
        workspaceId: botContext.workspaceId,
      };

      return true;
    }

    // WebSocket — delegate to gateway-level auth
    return true;
  }
}
