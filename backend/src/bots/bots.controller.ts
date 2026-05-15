import {
  Controller,
  Get,
  Post,
  Patch,
  Delete,
  Body,
  Param,
  UseGuards,
  Req,
} from '@nestjs/common';
import { Request } from 'express';
import { JwtAuthGuard } from '../auth/jwt.guard';
import { BotsService } from './bots.service';
import {
  CreateBotDto,
  UpdateBotDto,
  CreateCommandDto,
  UpdateCommandDto,
  SubscribeEventDto,
} from './dto/bot.dto';

@Controller('workspaces/:workspaceId/bots')
@UseGuards(JwtAuthGuard)
export class BotsController {
  constructor(private readonly botsService: BotsService) {}

  @Post()
  async create(
    @Param('workspaceId') workspaceId: string,
    @Body() dto: CreateBotDto,
    @Req() req: Request & { user: { id: string } },
  ) {
    return this.botsService.createBot(workspaceId, req.user.id, dto);
  }

  @Get()
  async list(
    @Param('workspaceId') workspaceId: string,
    @Req() req: Request & { user: { id: string } },
  ) {
    return this.botsService.listBots(workspaceId, req.user.id);
  }

  @Get(':botId')
  async get(
    @Param('workspaceId') workspaceId: string,
    @Param('botId') botId: string,
    @Req() req: Request & { user: { id: string } },
  ) {
    return this.botsService.getBot(workspaceId, botId, req.user.id);
  }

  @Patch(':botId')
  async update(
    @Param('workspaceId') workspaceId: string,
    @Param('botId') botId: string,
    @Body() dto: UpdateBotDto,
    @Req() req: Request & { user: { id: string } },
  ) {
    return this.botsService.updateBot(workspaceId, botId, req.user.id, dto);
  }

  @Delete(':botId')
  async remove(
    @Param('workspaceId') workspaceId: string,
    @Param('botId') botId: string,
    @Req() req: Request & { user: { id: string } },
  ) {
    return this.botsService.deleteBot(workspaceId, botId, req.user.id);
  }

  // API Keys
  @Post(':botId/keys')
  async createKey(
    @Param('workspaceId') workspaceId: string,
    @Param('botId') botId: string,
    @Req() req: Request & { user: { id: string } },
  ) {
    return this.botsService.generateApiKey(workspaceId, botId, req.user.id);
  }

  @Get(':botId/keys')
  async listKeys(
    @Param('workspaceId') workspaceId: string,
    @Param('botId') botId: string,
    @Req() req: Request & { user: { id: string } },
  ) {
    return this.botsService.listApiKeys(workspaceId, botId, req.user.id);
  }

  @Delete(':botId/keys/:keyId')
  async revokeKey(
    @Param('workspaceId') workspaceId: string,
    @Param('botId') botId: string,
    @Param('keyId') keyId: string,
    @Req() req: Request & { user: { id: string } },
  ) {
    return this.botsService.revokeApiKey(workspaceId, botId, keyId, req.user.id);
  }

  // Commands
  @Post(':botId/commands')
  async addCommand(
    @Param('workspaceId') workspaceId: string,
    @Param('botId') botId: string,
    @Body() dto: CreateCommandDto,
    @Req() req: Request & { user: { id: string } },
  ) {
    return this.botsService.addCommand(workspaceId, botId, req.user.id, dto);
  }

  @Get(':botId/commands')
  async listCommands(
    @Param('workspaceId') workspaceId: string,
    @Param('botId') botId: string,
    @Req() req: Request & { user: { id: string } },
  ) {
    return this.botsService.listCommands(workspaceId, botId, req.user.id);
  }

  @Patch(':botId/commands/:commandId')
  async updateCommand(
    @Param('workspaceId') workspaceId: string,
    @Param('botId') botId: string,
    @Param('commandId') commandId: string,
    @Body() dto: UpdateCommandDto,
    @Req() req: Request & { user: { id: string } },
  ) {
    return this.botsService.updateCommand(workspaceId, botId, commandId, req.user.id, dto);
  }

  @Delete(':botId/commands/:commandId')
  async removeCommand(
    @Param('workspaceId') workspaceId: string,
    @Param('botId') botId: string,
    @Param('commandId') commandId: string,
    @Req() req: Request & { user: { id: string } },
  ) {
    return this.botsService.removeCommand(workspaceId, botId, commandId, req.user.id);
  }

  // Events
  @Post(':botId/events')
  async subscribe(
    @Param('workspaceId') workspaceId: string,
    @Param('botId') botId: string,
    @Body() dto: SubscribeEventDto,
    @Req() req: Request & { user: { id: string } },
  ) {
    return this.botsService.subscribeEvent(workspaceId, botId, req.user.id, dto.event);
  }

  @Get(':botId/events')
  async listEvents(
    @Param('workspaceId') workspaceId: string,
    @Param('botId') botId: string,
    @Req() req: Request & { user: { id: string } },
  ) {
    return this.botsService.listEventSubscriptions(workspaceId, botId, req.user.id);
  }

  @Delete(':botId/events/:subId')
  async unsubscribe(
    @Param('workspaceId') workspaceId: string,
    @Param('botId') botId: string,
    @Param('subId') subId: string,
    @Req() req: Request & { user: { id: string } },
  ) {
    return this.botsService.unsubscribeEvent(workspaceId, botId, subId, req.user.id);
  }

  // Available events
  @Get('~available-events')
  getAvailableEvents() {
    return { events: this.botsService.getAvailableEvents() };
  }
}
