import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { ConfigService } from '@nestjs/config';
import { BotsService } from './bots.service';
import { BotsController } from './bots.controller';
import { BotsGateway } from './bots.gateway';
import { BotAuthGuard } from './bots-auth.guard';
import { SharedModule } from '../shared/shared.module';
import { PrismaModule } from '../database/prisma.module';


@Module({
  imports: [
    PrismaModule,
    SharedModule,
    JwtModule.registerAsync({
      inject: [ConfigService],
      useFactory: (config: ConfigService) => ({
        secret: config.get<string>('JWT_SECRET'),
        signOptions: { expiresIn: '12h' },
      }),
    }),
  ],
  controllers: [BotsController],
  providers: [BotsService, BotsGateway, BotAuthGuard],
  exports: [BotsService, BotsGateway, BotAuthGuard],
})
export class BotsModule {}
