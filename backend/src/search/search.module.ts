import { Module } from '@nestjs/common';

import { AuthModule } from '../auth/auth.module';
import { PrismaModule } from '../database/prisma.module';
import { SharedModule } from '../shared/shared.module';
import { SearchController } from './search.controller';
import { SearchService } from './search.service';

@Module({
  imports: [PrismaModule, SharedModule, AuthModule],
  controllers: [SearchController],
  providers: [SearchService],
})
export class SearchModule {}
