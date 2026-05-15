import {
  Controller,
  Get,
  Patch,
  Delete,
  Param,
  Body,
  UseGuards,
  Req,
} from '@nestjs/common';
import { Request } from 'express';
import { WorkspaceRole } from '@prisma/client';
import { JwtAuthGuard } from '../auth/jwt.guard';
import { AdminService } from './admin.service';

@Controller('workspaces/:wid')
@UseGuards(JwtAuthGuard)
export class AdminController {
  constructor(private readonly adminService: AdminService) {}

  @Get('members')
  async listMembers(
    @Param('wid') workspaceId: string,
    @Req() req: Request & { user: { id: string } },
  ) {
    return this.adminService.listMembers(workspaceId, req.user.id);
  }

  @Patch('members/:uid/role')
  async changeRole(
    @Param('wid') workspaceId: string,
    @Param('uid') targetUserId: string,
    @Body('role') role: WorkspaceRole,
    @Req() req: Request & { user: { id: string } },
  ) {
    return this.adminService.changeRole(workspaceId, targetUserId, req.user.id, role);
  }

  @Delete('members/:uid')
  async removeMember(
    @Param('wid') workspaceId: string,
    @Param('uid') targetUserId: string,
    @Req() req: Request & { user: { id: string } },
  ) {
    return this.adminService.removeMember(workspaceId, targetUserId, req.user.id);
  }

  @Get('audit')
  async getAuditLog(
    @Param('wid') workspaceId: string,
    @Req() req: Request & { user: { id: string } },
  ) {
    return this.adminService.getAuditLog(workspaceId, req.user.id);
  }

  @Get('storage')
  async getStorageStats(
    @Param('wid') workspaceId: string,
    @Req() req: Request & { user: { id: string } },
  ) {
    return this.adminService.getStorageStats(workspaceId, req.user.id);
  }
}
