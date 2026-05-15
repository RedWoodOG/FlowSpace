import {
  BadRequestException,
  Controller,
  Get,
  Param,
  Query,
  Req,
  UseGuards,
} from '@nestjs/common';
import type { Request } from 'express';

import { JwtAuthGuard } from '../auth/jwt.guard';
import { SearchService } from './search.service';

@Controller('workspaces/:wid/search')
export class SearchController {
  constructor(private readonly searchService: SearchService) {}

  @UseGuards(JwtAuthGuard)
  @Get()
  async search(
    @Req() req: Request & {
      user?: { id: string; email?: string; displayName?: string | null };
    },
    @Param('wid') wid: string,
    @Query('q') q?: string,
    @Query('type') type?: string,
  ) {
    if (!q || q.trim().length === 0) {
      throw new BadRequestException('Search query is required');
    }

    const query = q.trim();

    switch (type) {
      case 'messages':
        return this.searchService.searchMessages(wid, query);
      case 'files':
        return this.searchService.searchFiles(wid, query);
      case 'projects':
        return this.searchService.searchProjects(wid, query);
      case 'all':
      default:
        return this.searchService.searchAll(wid, query);
    }
  }
}
