import {
  Injectable,
  NotFoundException,
  ForbiddenException,
  ConflictException,
} from '@nestjs/common';
import { randomBytes, randomUUID } from 'crypto';
import { hash, compare } from 'bcrypt';
import { PrismaService } from '../database/prisma.service';
import { WorkspaceRole, BotHandlerType } from '@prisma/client';

@Injectable()
export class BotsService {
  constructor(private readonly prisma: PrismaService) {}

  private readonly API_KEY_PREFIX = 'flo_';

  async createBot(
    workspaceId: string,
    userId: string,
    data: { name: string; displayName: string; description?: string; avatarUrl?: string },
  ) {
    await this.requireAdmin(workspaceId, userId);

    const existing = await this.prisma.bot.findFirst({
      where: { workspaceId, name: data.name },
    });
    if (existing) {
      throw new ConflictException('A bot with this name already exists in the workspace');
    }

    return this.prisma.bot.create({
      data: {
        workspaceId,
        name: data.name,
        displayName: data.displayName,
        description: data.description,
        avatarUrl: data.avatarUrl,
        createdBy: userId,
      },
    });
  }

  async listBots(workspaceId: string, userId: string) {
    await this.requireMember(workspaceId, userId);

    return this.prisma.bot.findMany({
      where: { workspaceId },
      include: {
        _count: {
          select: {
            commands: { where: { enabled: true } },
            events: { where: { enabled: true } },
          },
        },
      },
      orderBy: { createdAt: 'desc' },
    });
  }

  async getBot(workspaceId: string, botId: string, userId: string) {
    await this.requireMember(workspaceId, userId);

    const bot = await this.prisma.bot.findFirst({
      where: { id: botId, workspaceId },
      include: {
        commands: true,
        events: true,
        apiKeys: {
          select: {
            id: true,
            prefix: true,
            lastUsed: true,
            expiresAt: true,
            createdAt: true,
          },
        },
      },
    });

    if (!bot) {
      throw new NotFoundException('Bot not found');
    }

    return bot;
  }

  async updateBot(
    workspaceId: string,
    botId: string,
    userId: string,
    data: { displayName?: string; description?: string; avatarUrl?: string; active?: boolean },
  ) {
    await this.requireAdmin(workspaceId, userId);

    const bot = await this.requireBotOwnership(workspaceId, botId);

    const updateData: any = {};
    if (data.displayName !== undefined) updateData.displayName = data.displayName;
    if (data.description !== undefined) updateData.description = data.description;
    if (data.avatarUrl !== undefined) updateData.avatarUrl = data.avatarUrl;
    if (data.active !== undefined) {
      updateData.status = data.active ? 'ACTIVE' : 'DISABLED';
    }

    return this.prisma.bot.update({
      where: { id: botId },
      data: updateData,
    });
  }

  async deleteBot(workspaceId: string, botId: string, userId: string) {
    await this.requireAdmin(workspaceId, userId);
    await this.requireBotOwnership(workspaceId, botId);

    await this.prisma.bot.delete({ where: { id: botId } });
    return { success: true };
  }

  async generateApiKey(workspaceId: string, botId: string, userId: string) {
    await this.requireAdmin(workspaceId, userId);
    await this.requireBotOwnership(workspaceId, botId);

    const rawKey = `${this.API_KEY_PREFIX}${randomBytes(32).toString('hex')}`;
    const keyHash = await hash(rawKey, 8);
    const prefix = rawKey.substring(0, 15) + '...';

    await this.prisma.botApiKey.create({
      data: {
        botId,
        keyHash,
        prefix,
      },
    });

    return { apiKey: rawKey, prefix };
  }

  async listApiKeys(workspaceId: string, botId: string, userId: string) {
    await this.requireAdmin(workspaceId, userId);
    await this.requireBotOwnership(workspaceId, botId);

    return this.prisma.botApiKey.findMany({
      where: { botId },
      select: {
        id: true,
        prefix: true,
        lastUsed: true,
        expiresAt: true,
        createdAt: true,
      },
      orderBy: { createdAt: 'desc' },
    });
  }

  async revokeApiKey(workspaceId: string, botId: string, keyId: string, userId: string) {
    await this.requireAdmin(workspaceId, userId);
    await this.requireBotOwnership(workspaceId, botId);

    const key = await this.prisma.botApiKey.findFirst({
      where: { id: keyId, botId },
    });

    if (!key) {
      throw new NotFoundException('API key not found');
    }

    await this.prisma.botApiKey.delete({ where: { id: keyId } });
    return { success: true };
  }

  async addCommand(
    workspaceId: string,
    botId: string,
    userId: string,
    data: { command: string; description: string; handlerType?: string; handlerUrl?: string },
  ) {
    await this.requireAdmin(workspaceId, userId);
    await this.requireBotOwnership(workspaceId, botId);

    const existing = await this.prisma.botCommand.findFirst({
      where: { botId, command: data.command },
    });
    if (existing) {
      throw new ConflictException('This command is already registered');
    }

    return this.prisma.botCommand.create({
      data: {
        botId,
        command: data.command,
        description: data.description,
        handlerType: (data.handlerType as BotHandlerType) || BotHandlerType.WEBSOCKET,
        handlerUrl: data.handlerUrl,
      },
    });
  }

  async listCommands(workspaceId: string, botId: string, userId: string) {
    await this.requireMember(workspaceId, userId);
    return this.prisma.botCommand.findMany({
      where: { botId },
      orderBy: { createdAt: 'asc' },
    });
  }

  async updateCommand(
    workspaceId: string,
    botId: string,
    commandId: string,
    userId: string,
    data: { description?: string; enabled?: boolean; handlerType?: string; handlerUrl?: string },
  ) {
    await this.requireAdmin(workspaceId, userId);
    await this.requireBotOwnership(workspaceId, botId);

    const cmd = await this.prisma.botCommand.findFirst({
      where: { id: commandId, botId },
    });
    if (!cmd) {
      throw new NotFoundException('Command not found');
    }

    return this.prisma.botCommand.update({
      where: { id: commandId },
      data: {
        ...data,
        handlerType: data.handlerType ? (data.handlerType as BotHandlerType) : undefined,
      },
    });
  }

  async removeCommand(workspaceId: string, botId: string, commandId: string, userId: string) {
    await this.requireAdmin(workspaceId, userId);
    await this.requireBotOwnership(workspaceId, botId);

    const cmd = await this.prisma.botCommand.findFirst({
      where: { id: commandId, botId },
    });
    if (!cmd) {
      throw new NotFoundException('Command not found');
    }

    await this.prisma.botCommand.delete({ where: { id: commandId } });
    return { success: true };
  }

  async subscribeEvent(
    workspaceId: string,
    botId: string,
    userId: string,
    event: string,
  ) {
    await this.requireAdmin(workspaceId, userId);
    await this.requireBotOwnership(workspaceId, botId);

    const existing = await this.prisma.botEventSubscription.findFirst({
      where: { botId, event },
    });
    if (existing) {
      throw new ConflictException('Already subscribed to this event');
    }

    return this.prisma.botEventSubscription.create({
      data: { botId, event },
    });
  }

  async listEventSubscriptions(workspaceId: string, botId: string, userId: string) {
    await this.requireMember(workspaceId, userId);
    return this.prisma.botEventSubscription.findMany({
      where: { botId },
      orderBy: { createdAt: 'asc' },
    });
  }

  async unsubscribeEvent(
    workspaceId: string,
    botId: string,
    subscriptionId: string,
    userId: string,
  ) {
    await this.requireAdmin(workspaceId, userId);
    await this.requireBotOwnership(workspaceId, botId);

    const sub = await this.prisma.botEventSubscription.findFirst({
      where: { id: subscriptionId, botId },
    });
    if (!sub) {
      throw new NotFoundException('Event subscription not found');
    }

    await this.prisma.botEventSubscription.delete({ where: { id: subscriptionId } });
    return { success: true };
  }

  // ===== Auth helpers =====

  async validateApiKey(apiKey: string): Promise<{ id: string; botId: string; workspaceId: string } | null> {
    const prefix = apiKey.substring(0, 15);

    const keys = await this.prisma.botApiKey.findMany({
      where: { prefix },
      include: { bot: true },
    });

    for (const keyRecord of keys) {
      const valid = await compare(apiKey, keyRecord.keyHash);
      if (valid && keyRecord.bot.status === 'ACTIVE') {
        await this.prisma.botApiKey.update({
          where: { id: keyRecord.id },
          data: { lastUsed: new Date() },
        });
        return {
          id: keyRecord.id,
          botId: keyRecord.botId,
          workspaceId: keyRecord.bot.workspaceId,
        };
      }
    }

    return null;
  }

  async findCommandInWorkspace(workspaceId: string, commandText: string) {
    const commandRoot = commandText.split(' ')[0].toLowerCase();

    return this.prisma.botCommand.findFirst({
      where: {
        command: commandRoot,
        enabled: true,
        bot: {
          workspaceId,
          status: 'ACTIVE',
        },
      },
      include: { bot: true },
    });
  }

  getAvailableEvents(): string[] {
    return [
      'message.new',
      'message.edited',
      'message.deleted',
      'channel.created',
      'user.joined',
      'user.left',
      'reaction.added',
      'reaction.removed',
      'mention.received',
    ];
  }

  async getBotSubscribedEvents(botId: string): Promise<string[]> {
    const subs = await this.prisma.botEventSubscription.findMany({
      where: { botId, enabled: true },
    });
    return subs.map(s => s.event);
  }

  // ===== Permission helpers =====

  private async requireAdmin(workspaceId: string, userId: string) {
    const membership = await this.prisma.workspaceMember.findFirst({
      where: { workspaceId, userId },
    });

    if (!membership || (membership.role !== WorkspaceRole.ADMIN && membership.role !== WorkspaceRole.OWNER)) {
      throw new ForbiddenException('Admin access required');
    }
  }

  private async requireMember(workspaceId: string, userId: string) {
    const membership = await this.prisma.workspaceMember.findFirst({
      where: { workspaceId, userId },
    });

    if (!membership) {
      throw new ForbiddenException('Workspace membership required');
    }
  }

  private async requireBotOwnership(workspaceId: string, botId: string) {
    const bot = await this.prisma.bot.findFirst({
      where: { id: botId, workspaceId },
    });

    if (!bot) {
      throw new NotFoundException('Bot not found in this workspace');
    }

    return bot;
  }
}
