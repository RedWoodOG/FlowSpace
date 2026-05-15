import { Injectable } from '@nestjs/common';

import { PrismaService } from '../database/prisma.service';

export interface SearchResult {
  type: 'message' | 'file' | 'project';
  id: string;
  title: string;
  subtitle?: string;
  workspaceId: string;
  createdAt: string;
}

@Injectable()
export class SearchService {
  constructor(private readonly prisma: PrismaService) {}

  async searchMessages(
    workspaceId: string,
    query: string,
  ): Promise<SearchResult[]> {
    const messages = await this.prisma.chatMessage.findMany({
      where: {
        content: { contains: query, mode: 'insensitive' },
        deleted: false,
        channel: { workspaceId },
      },
      include: {
        channel: true,
        sender: true,
      },
      orderBy: { createdAt: 'desc' },
      take: 50,
    });

    return messages.map((msg) => ({
      type: 'message' as const,
      id: msg.id,
      title: msg.content.length > 200 ? msg.content.slice(0, 200) + '…' : msg.content,
      subtitle: `#${msg.channel.name} — ${msg.sender.nickname ?? msg.sender.displayName ?? msg.sender.email}`,
      workspaceId,
      createdAt: msg.createdAt.toISOString(),
    }));
  }

  async searchFiles(
    workspaceId: string,
    query: string,
  ): Promise<SearchResult[]> {
    const files = await this.prisma.vaultFile.findMany({
      where: {
        workspaceId,
        name: { contains: query, mode: 'insensitive' },
      },
      orderBy: { createdAt: 'desc' },
      take: 50,
    });

    return files.map((file) => ({
      type: 'file' as const,
      id: file.id,
      title: file.name,
      subtitle: `${(file.size / 1024).toFixed(1)} KB`,
      workspaceId,
      createdAt: file.createdAt.toISOString(),
    }));
  }

  async searchProjects(
    workspaceId: string,
    query: string,
  ): Promise<SearchResult[]> {
    const projects = await this.prisma.project.findMany({
      where: {
        workspaceId,
        name: { contains: query, mode: 'insensitive' },
      },
      orderBy: { createdAt: 'desc' },
      take: 50,
    });

    return projects.map((project) => ({
      type: 'project' as const,
      id: project.id,
      title: project.name,
      subtitle: `Created by ${project.createdBy}`,
      workspaceId,
      createdAt: project.createdAt.toISOString(),
    }));
  }

  async searchAll(
    workspaceId: string,
    query: string,
  ): Promise<SearchResult[]> {
    const [messages, files, projects] = await Promise.all([
      this.searchMessages(workspaceId, query),
      this.searchFiles(workspaceId, query),
      this.searchProjects(workspaceId, query),
    ]);

    return [...messages, ...files, ...projects].sort(
      (a, b) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime(),
    );
  }
}
