import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { WorkspaceRole } from '@prisma/client';

import { PrismaService } from '../database/prisma.service';
import { RedisService } from '../shared/redis.service';
import {
  WorkspaceEvents,
  ChatMessagePayload,
  ChannelCreatedPayload,
} from '../../libs/shared';

interface CreateMessageInput {
  workspaceId: string;
  channelId: string;
  senderId?: string;
  content: string;
  attachments?: string[];
  parentId?: string | null;
}

interface CreateChannelInput {
  workspaceId: string;
  creatorId?: string;
  name: string;
  description?: string;
  private?: boolean;
}

@Injectable()
export class ChatService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly redis: RedisService,
  ) {}

  async listChannels(workspaceId: string, userId?: string) {
    if (userId) {
      const membership = await this.prisma.workspaceMember.findFirst({
        where: { workspaceId, userId },
      });
      if (!membership) {
        throw new ForbiddenException('User is not a member of this workspace');
      }
    }

    // TODO: N+1 query — consider raw query or batch load for last message per channel
    const channels = await this.prisma.channel.findMany({
      where: { workspaceId },
      include: {
        messages: {
          take: 1,
          orderBy: { createdAt: 'desc' },
          include: { sender: true },
        },
      },
      orderBy: { updatedAt: 'desc' },
    });

    return channels.map((channel) => ({
      id: channel.id,
      name: channel.name,
      description: channel.description,
      updatedAt: channel.updatedAt.toISOString(),
      lastMessage: channel.messages[0]
        ? {
            id: channel.messages[0].id,
            senderId: channel.messages[0].senderId,
            senderName: channel.messages[0].sender.nickname ?? channel.messages[0].sender.displayName ?? null,
            content: channel.messages[0].content,
            createdAt: channel.messages[0].createdAt.toISOString(),
          }
        : null,
    }));
  }

  async getChannelMessages(
    workspaceId: string,
    channelId: string,
    userId?: string,
    limit = 200,
  ) {
    const channel = await this.prisma.channel.findUnique({
      where: { id: channelId },
      include: { workspace: true },
    });

    if (!channel || channel.workspaceId !== workspaceId) {
      throw new NotFoundException('Channel not found');
    }

    if (userId) {
      const membership = await this.prisma.workspaceMember.findFirst({
        where: { workspaceId, userId },
      });
      if (!membership) {
        throw new ForbiddenException('User is not a member of this workspace');
      }
    }

    const messages = await this.prisma.chatMessage.findMany({
      where: { channelId },
      orderBy: { createdAt: 'asc' },
      take: limit,
      include: {
        sender: true,
        _count: {
          select: { replies: true },
        },
      },
    });

    return {
      channel: {
        id: channel.id,
        name: channel.name,
        description: channel.description,
        workspaceId: channel.workspaceId,
      },
      messages: messages.map((message) => ({
        id: message.id,
        channelId: message.channelId,
        senderId: message.senderId,
        senderName: message.sender.nickname ?? message.sender.displayName ?? null,
        content: message.content,
        attachments: message.attachments,
        parentId: message.parentId ?? null,
        reactions: this.formatReactions(message.reactions),
        edited: message.edited,
        editedAt: message.editedAt?.toISOString() ?? null,
        deleted: message.deleted,
        deletedAt: message.deletedAt?.toISOString() ?? null,
        pinned: message.pinned,
        pinnedAt: message.pinnedAt?.toISOString() ?? null,
        pinnedBy: message.pinnedBy ?? null,
        threadCount: message._count.replies,
        createdAt: message.createdAt.toISOString(),
      })),
    };
  }

  async createChannel({
    workspaceId,
    creatorId,
    name,
    description,
    private: isPrivate,
  }: CreateChannelInput) {
    if (!creatorId) {
      throw new ForbiddenException('Creator is required');
    }

    const membership = await this.prisma.workspaceMember.findFirst({
      where: { workspaceId, userId: creatorId },
      include: {
        workspace: true,
      },
    });

    if (!membership) {
      throw new ForbiddenException('User is not a member of this workspace');
    }

    if (
      membership.role !== WorkspaceRole.OWNER &&
      membership.role !== WorkspaceRole.ADMIN
    ) {
      throw new ForbiddenException('Only workspace admins can create channels');
    }

    const normalizedName = name?.trim();
    if (!normalizedName) {
      throw new BadRequestException('Channel name is required');
    }

    if (description && description.length > 2000) {
      throw new BadRequestException('Description is too long');
    }

    if (isPrivate) {
      throw new BadRequestException('Private channels are not supported yet');
    }

    const duplicate = await this.prisma.channel.findFirst({
      where: {
        workspaceId,
        name: normalizedName,
      },
      select: { id: true },
    });

    if (duplicate) {
      throw new ConflictException('A channel with this name already exists');
    }

    const channel = await this.prisma.channel.create({
      data: {
        workspaceId,
        name: normalizedName,
        description,
      },
    });

    const payload: ChannelCreatedPayload = {
      workspaceId,
      createdBy: creatorId,
      channel: {
        id: channel.id,
        name: channel.name,
        description: channel.description ?? null,
        createdAt: channel.createdAt.toISOString(),
        updatedAt: channel.updatedAt.toISOString(),
      },
    };

    await this.redis.publish(WorkspaceEvents.CHANNEL_CREATED, payload);

    return payload;
  }


  async sendMessage({
    workspaceId,
    channelId,
    senderId,
    content,
    attachments = [],
    parentId = null,
  }: CreateMessageInput) {
    if (!senderId) {
      throw new ForbiddenException('Sender is required');
    }

    const channel = await this.prisma.channel.findUnique({
      where: { id: channelId },
      include: { workspace: true },
    });

    if (!channel || channel.workspaceId !== workspaceId) {
      throw new NotFoundException('Channel not found');
    }

    const membership = await this.prisma.workspaceMember.findFirst({
      where: { workspaceId, userId: senderId },
    });

    if (!membership) {
      throw new ForbiddenException('User is not a member of this workspace');
    }

    // Validate parent message if parentId is provided
    // Message content length limit
    if (content.length > 50000) throw new BadRequestException('Message too long');

    if (parentId) {
      const parentMessage = await this.prisma.chatMessage.findUnique({
        where: { id: parentId },
      });

      if (!parentMessage || parentMessage.channelId !== channelId) {
        throw new NotFoundException('Parent message not found or in different channel');
      }
    }

    // Detect mentions in content
    const mentions = this.extractMentions(content);

    const [message] = await this.prisma.$transaction([
      this.prisma.chatMessage.create({
        data: {
          channelId,
          senderId,
          content,
          attachments,
          parentId,
        },
        include: { sender: true },
      }),
      this.prisma.channel.update({
        where: { id: channelId },
        data: { updatedAt: new Date() },
      }),
    ]);

    const payload: ChatMessagePayload = {
      id: message.id,
      channelId: message.channelId,
      senderId: message.senderId,
      senderName: message.sender.displayName ?? null,
      content: message.content,
      attachments: message.attachments,
      parentId: message.parentId ?? null,
      timestamp: message.createdAt.toISOString(),
    };

    await this.redis.publish(WorkspaceEvents.MESSAGE_SENT, {
      workspaceId: channel.workspaceId,
      message: payload,
    });

    // Broadcast mentions if any
    if (mentions.length > 0) {
      await this.redis.publish('mention.received', {
        messageId: message.id,
        channelId: message.channelId,
        senderId: message.senderId,
        senderName: message.sender.displayName ?? null,
        mentions,
        content: message.content,
      });
    }

    return { message: payload };
  }

  async addReaction(
    messageId: string,
    userId: string,
    emoji: string,
  ) {
    const updated = await this.prisma.$transaction(async (tx) => {
      const msg = await tx.chatMessage.findUnique({ where: { id: messageId } });
      if (!msg) throw new NotFoundException('Message not found');
      const reactions = (msg.reactions as any[]) || [];
      if (reactions.find((r: any) => r.userId === userId && r.emoji === emoji)) {
        throw new ConflictException('Reaction already exists');
      }
      reactions.push({ emoji, userId, timestamp: new Date().toISOString() });
      return tx.chatMessage.update({ where: { id: messageId }, data: { reactions } });
    });

    await this.redis.publish('reaction.added', {
      messageId,
      channelId: updated.channelId,
      userId,
      emoji,
      reactions: this.formatReactions(updated.reactions),
    });

    return { reactions: this.formatReactions(updated.reactions) };
  }

  async removeReaction(
    messageId: string,
    userId: string,
    emoji: string,
  ) {
    const updated = await this.prisma.$transaction(async (tx) => {
      const msg = await tx.chatMessage.findUnique({ where: { id: messageId } });
      if (!msg) throw new NotFoundException('Message not found');
      let reactions = (msg.reactions as any[]) || [];
      reactions = reactions.filter(
        (r: any) => !(r.userId === userId && r.emoji === emoji),
      );
      return tx.chatMessage.update({ where: { id: messageId }, data: { reactions } });
    });

    await this.redis.publish('reaction.removed', {
      messageId,
      channelId: updated.channelId,
      userId,
      emoji,
      reactions: this.formatReactions(updated.reactions),
    });

    return { reactions: this.formatReactions(updated.reactions) };
  }

  async editMessage(
    messageId: string,
    userId: string,
    newContent: string,
  ) {
    const message = await this.prisma.chatMessage.findUnique({
      where: { id: messageId },
      include: { sender: true },
    });

    if (!message) {
      throw new NotFoundException('Message not found');
    }

    if (message.senderId !== userId) {
      throw new ForbiddenException('You can only edit your own messages');
    }

    const updated = await this.prisma.chatMessage.update({
      where: { id: messageId },
      data: {
        content: newContent,
        edited: true,
        editedAt: new Date(),
      },
      include: { sender: true },
    });

    await this.redis.publish('message.edited', {
      id: updated.id,
      channelId: updated.channelId,
      senderId: updated.senderId,
      senderName: updated.sender.displayName ?? null,
      content: updated.content,
      edited: updated.edited,
      editedAt: updated.editedAt?.toISOString(),
    });

    return { message: updated };
  }

  async deleteMessage(messageId: string, userId: string) {
    const message = await this.prisma.chatMessage.findUnique({
      where: { id: messageId },
    });

    if (!message) {
      throw new NotFoundException('Message not found');
    }

    // Allow sender or workspace admins to delete
    const membership = await this.prisma.workspaceMember.findFirst({
      where: {
        userId,
        workspace: {
          channels: {
            some: { id: message.channelId },
          },
        },
      },
    });

    if (
      message.senderId !== userId &&
      membership?.role !== WorkspaceRole.ADMIN &&
      membership?.role !== WorkspaceRole.OWNER
    ) {
      throw new ForbiddenException(
        'You can only delete your own messages or must be an admin',
      );
    }

    await this.prisma.chatMessage.update({
      where: { id: messageId },
      data: {
        deleted: true,
        deletedAt: new Date(),
        content: '',
      },
    });

    await this.redis.publish('message.deleted', {
      messageId,
      channelId: message.channelId,
    });

    return { success: true };
  }

  async getThreadMessages(parentId: string, userId?: string, limit = 100) {
    const parent = await this.prisma.chatMessage.findUnique({
      where: { id: parentId },
      include: { sender: true, channel: true },
    });

    if (!parent) {
      throw new NotFoundException('Parent message not found');
    }

    if (userId) {
      const membership = await this.prisma.workspaceMember.findFirst({
        where: {
          userId,
          workspaceId: parent.channel.workspaceId,
        },
      });

      if (!membership) {
        throw new ForbiddenException('User is not a member of this workspace');
      }
    }

    const replies = await this.prisma.chatMessage.findMany({
      where: { parentId },
      orderBy: { createdAt: 'asc' },
      take: limit,
      include: { sender: true },
    });

    return {
      parent: {
        id: parent.id,
        channelId: parent.channelId,
        senderId: parent.senderId,
        senderName: parent.sender.displayName ?? null,
        content: parent.content,
        reactions: this.formatReactions(parent.reactions),
        createdAt: parent.createdAt.toISOString(),
      },
      replies: replies.map((reply) => ({
        id: reply.id,
        channelId: reply.channelId,
        senderId: reply.senderId,
        senderName: reply.sender.displayName ?? null,
        content: reply.content,
        reactions: this.formatReactions(reply.reactions),
        createdAt: reply.createdAt.toISOString(),
      })),
    };
  }

  async markAsRead(messageId: string, userId: string) {
    await this.prisma.messageRead.upsert({
      where: {
        messageId_userId: { messageId, userId },
      },
      create: { messageId, userId },
      update: { readAt: new Date() },
    });

    await this.redis.publish('message.read', {
      messageId,
      userId,
      readAt: new Date().toISOString(),
    });

    return { success: true };
  }

  async getReadReceipts(messageId: string) {
    const reads = await this.prisma.messageRead.findMany({
      where: { messageId },
    });

    return reads.map((read) => ({
      userId: read.userId,
      readAt: read.readAt.toISOString(),
    }));
  }

  private extractMentions(content: string): string[] {
    const mentionRegex = /@([a-zA-Z0-9_]+)/g;
    const matches = content.matchAll(mentionRegex);
    return Array.from(matches).map((match) => match[1]);
  }

  async pinMessage(messageId: string, userId: string) {
    // TODO: combine membership check with message fetch in single query for efficiency

    const message = await this.prisma.chatMessage.findUnique({
      where: { id: messageId },
      include: { channel: true },
    });

    if (!message) {
      throw new NotFoundException('Message not found');
    }

    // Check if user is admin or owner
    const membership = await this.prisma.workspaceMember.findFirst({
      where: {
        userId,
        workspaceId: message.channel.workspaceId,
      },
    });

    if (
      membership?.role !== WorkspaceRole.ADMIN &&
      membership?.role !== WorkspaceRole.OWNER
    ) {
      throw new ForbiddenException('Only admins can pin messages');
    }

    const updated = await this.prisma.chatMessage.update({
      where: { id: messageId },
      data: {
        pinned: true,
        pinnedAt: new Date(),
        pinnedBy: userId,
      },
    });

    await this.redis.publish('message.pinned', {
      messageId,
      channelId: message.channelId,
      pinnedBy: userId,
    });

    return { message: updated };
  }

  async unpinMessage(messageId: string, userId: string) {
    const message = await this.prisma.chatMessage.findUnique({
      where: { id: messageId },
      include: { channel: true },
    });
    // TODO: combine membership check with message fetch in single query for efficiency


    if (!message) {
      throw new NotFoundException('Message not found');
    }

    // Check if user is admin or owner
    const membership = await this.prisma.workspaceMember.findFirst({
      where: {
        userId,
        workspaceId: message.channel.workspaceId,
      },
    });

    if (
      membership?.role !== WorkspaceRole.ADMIN &&
      membership?.role !== WorkspaceRole.OWNER
    ) {
      throw new ForbiddenException('Only admins can unpin messages');
    }

    const updated = await this.prisma.chatMessage.update({
      where: { id: messageId },
      data: {
        pinned: false,
        pinnedAt: null,
        pinnedBy: null,
      },
    });

    await this.redis.publish('message.unpinned', {
      messageId,
      channelId: message.channelId,
    });

    return { message: updated };
  }

  async getPinnedMessages(channelId: string, userId?: string) {
    const channel = await this.prisma.channel.findUnique({
      where: { id: channelId },
    });

    if (!channel) {
      throw new NotFoundException('Channel not found');
    }

    if (userId) {
      const membership = await this.prisma.workspaceMember.findFirst({
        where: {
          userId,
          workspaceId: channel.workspaceId,
        },
      });

      if (!membership) {
        throw new ForbiddenException('User is not a member of this workspace');
      }
    }

    const messages = await this.prisma.chatMessage.findMany({
      where: {
        channelId,
        pinned: true,
      },
      orderBy: { pinnedAt: 'desc' },
      include: { sender: true },
    });

    return messages.map((message) => ({
      id: message.id,
      channelId: message.channelId,
      senderId: message.senderId,
      senderName: message.sender.displayName ?? null,
      content: message.content,
      pinned: message.pinned,
      pinnedAt: message.pinnedAt?.toISOString(),
      pinnedBy: message.pinnedBy,
      reactions: this.formatReactions(message.reactions),
      createdAt: message.createdAt.toISOString(),
    }));
  }

  private formatReactions(reactionsJson: unknown): Record<string, string[]> {
    if (!reactionsJson) {
      return {};
    }

    if (Array.isArray(reactionsJson)) {
      return reactionsJson.reduce<Record<string, string[]>>((acc, reaction) => {
        if (
          reaction &&
          typeof reaction === 'object' &&
          'emoji' in reaction &&
          'userId' in reaction
        ) {
          const emoji = String((reaction as { emoji: unknown }).emoji);
          const userId = String((reaction as { userId: unknown }).userId);
          acc[emoji] = [...(acc[emoji] ?? []), userId];
        }
        return acc;
      }, {});
    }

    if (typeof reactionsJson === 'object') {
      return reactionsJson as Record<string, string[]>;
    }

    return {};
  }
}
