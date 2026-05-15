import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';

import { AppController } from './app.controller';
import { AppService } from './app.service';
import { AuthModule } from './auth/auth.module';
import { ChatModule } from './chat/chat.module';
import { SystemModule } from './system/system.module';
import { WorkspacesModule } from './workspaces/workspaces.module';
import { VaultModule } from './vault/vault.module';
import { PresenceModule } from './presence/presence.module';
import { SignalingModule } from './signaling/signaling.module';
import { MeetModule } from './meet/meet.module';
import { UsersModule } from './users/users.module';
import { P2PGatewayModule } from './p2p-gateway/p2p-gateway.module';
import { P2PRuntimeModule } from './p2p-runtime/p2p-runtime.module';
import { UpdatesModule } from './updates/updates.module';
import { AssetsModule } from './assets/assets.module';
import { ProjectsModule } from './projects/projects.module';
import { AnalyticsModule } from './analytics/analytics.module';
import { AIModule } from './ai/ai.module';
import { DownloadsModule } from './downloads/downloads.module';
import { SearchModule } from './search/search.module';

import { BotsModule } from './bots/bots.module';
import { AdminModule } from './admin/admin.module';


@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true }),
    AuthModule,
    SystemModule,
    ChatModule,
    WorkspacesModule,
    VaultModule,
    PresenceModule,
    SignalingModule,
    MeetModule,
    UsersModule,
    P2PGatewayModule,
    P2PRuntimeModule,
    UpdatesModule,
    AssetsModule,
    BotsModule,
    AdminModule,
    ProjectsModule,
    AnalyticsModule,
    AIModule,
    DownloadsModule,
    SearchModule,
  ],
  controllers: [AppController],
  providers: [AppService],
})
export class AppModule {}
