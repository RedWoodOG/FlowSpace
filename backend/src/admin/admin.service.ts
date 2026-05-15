import {
  Injectable,
  NotFoundException,
  ForbiddenException,
  BadRequestException,
} from '@nestjs/common';
import { PrismaService } from '../database/prisma.service';
import { WorkspaceRole } from '@prisma/client';

const VALID_ROLES: WorkspaceRole[] = [
  WorkspaceRole.OWNER,
  WorkspaceRole.ADMIN,
  WorkspaceRole.MEMBER,
];

@Injectable()
export class AdminService {
  constructor(private readonly prisma: PrismaService) {}

  async listMembers(workspaceId: string, userId: string) {
    await this.requireMember(workspaceId, userId);

    const members = await this.prisma.workspaceMember.findMany({
      where: { workspaceId },
      include: {
        user: {
          select: {
            id: true,
            email: true,
            displayName: true,
            nickname: true,
            avatarUrl: true,
          },
        },
      },
      orderBy: { createdAt: 'asc' },
    });

    return members.map((m) => ({
      id: m.id,
      userId: m.userId,
      role: m.role,
      joinedAt: m.createdAt.toISOString(),
      user: m.user,
    }));
  }

  async changeRole(
    workspaceId: string,
    targetUserId: string,
    actorId: string,
    newRole: WorkspaceRole,
  ) {
    await this.requireAdmin(workspaceId, actorId);

    if (!VALID_ROLES.includes(newRole)) {
      throw new BadRequestException(
        `Invalid role: ${newRole}. Must be one of: ${VALID_ROLES.join(', ')}`,
      );
    }

    const targetMembership = await this.prisma.workspaceMember.findFirst({
      where: { workspaceId, userId: targetUserId },
    });

    if (!targetMembership) {
      throw new NotFoundException('User is not a member of this workspace');
    }

    // Only an OWNER can grant the OWNER role
    if (newRole === WorkspaceRole.OWNER) {
      const actorMembership = await this.prisma.workspaceMember.findFirst({
        where: { workspaceId, userId: actorId },
      });

      if (!actorMembership || actorMembership.role !== WorkspaceRole.OWNER) {
        throw new ForbiddenException('Only the workspace owner can transfer ownership');
      }
    }

    // Cannot demote yourself below ADMIN
    if (targetUserId === actorId && newRole !== WorkspaceRole.OWNER) {
      const actorMembership = await this.prisma.workspaceMember.findFirst({
        where: { workspaceId, userId: actorId },
      });
      if (actorMembership?.role === WorkspaceRole.OWNER) {
        throw new BadRequestException(
          'Cannot remove your own OWNER role. Transfer ownership to another member first.',
        );
      }
    }

    const updated = await this.prisma.workspaceMember.update({
      where: { id: targetMembership.id },
      data: { role: newRole },
      include: {
        user: {
          select: {
            id: true,
            email: true,
            displayName: true,
          },
        },
      },
    });

    return {
      id: updated.id,
      userId: updated.userId,
      role: updated.role,
      user: updated.user,
    };
  }

  async removeMember(workspaceId: string, targetUserId: string, actorId: string) {
    await this.requireAdmin(workspaceId, actorId);

    if (targetUserId === actorId) {
      throw new BadRequestException('You cannot remove yourself from the workspace');
    }

    const targetMembership = await this.prisma.workspaceMember.findFirst({
      where: { workspaceId, userId: targetUserId },
    });

    if (!targetMembership) {
      throw new NotFoundException('User is not a member of this workspace');
    }

    // An ADMIN cannot remove an OWNER
    if (targetMembership.role === WorkspaceRole.OWNER) {
      throw new ForbiddenException('Cannot remove the workspace owner');
    }

    await this.prisma.workspaceMember.delete({
      where: { id: targetMembership.id },
    });

    return { success: true };
  }

  async getAuditLog(workspaceId: string, userId: string) {
    await this.requireAdmin(workspaceId, userId);

    const logs = await this.prisma.auditLog.findMany({
      where: { workspaceId },
      orderBy: { createdAt: 'desc' },
      take: 100,
    });

    return logs.map((log) => ({
      id: log.id,
      userId: log.userId,
      action: log.action,
      entityType: log.entityType,
      entityId: log.entityId,
      metadata: log.metadata,
      createdAt: log.createdAt.toISOString(),
    }));
  }

  async getStorageStats(workspaceId: string, userId: string) {
    await this.requireMember(workspaceId, userId);

    const files = await this.prisma.vaultFile.findMany({
      where: { workspaceId },
      select: { id: true, size: true },
    });

    const totalFiles = files.length;
    const totalSize = files.reduce((sum, f) => sum + f.size, 0);

    return { totalFiles, totalSize };
  }

  // ===== Permission helpers =====

  private async requireAdmin(workspaceId: string, userId: string) {
    const membership = await this.prisma.workspaceMember.findFirst({
      where: { workspaceId, userId },
    });

    if (
      !membership ||
      (membership.role !== WorkspaceRole.ADMIN &&
        membership.role !== WorkspaceRole.OWNER)
    ) {
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
}
