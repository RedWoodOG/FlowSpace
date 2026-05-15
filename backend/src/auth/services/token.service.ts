import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { PrismaService } from '../../database/prisma.service';
import { hash, compare } from 'bcrypt';
import * as crypto from 'crypto';

@Injectable()
export class TokenService {
  constructor(
    private prisma: PrismaService,
    private config: ConfigService,
  ) {}

  generateVerificationToken(): string {
    return crypto.randomBytes(32).toString('hex');
  }

  generateRefreshToken(): string {
    return crypto.randomBytes(40).toString('hex');
  }

  async saveVerificationToken(userId: string, token: string): Promise<void> {
    const expiresAt = new Date();
    expiresAt.setHours(expiresAt.getHours() + 24); // 24 hours

    await this.prisma.verificationToken.create({
      data: { userId, token, expiresAt },
    });
  }

  async validateVerificationToken(token: string) {
    const verificationToken = await this.prisma.verificationToken.findUnique({
      where: { token },
      include: { user: true },
    });

    if (!verificationToken || verificationToken.expiresAt < new Date()) {
      return null;
    }

    return verificationToken;
  }

  async deleteVerificationToken(token: string): Promise<void> {
    await this.prisma.verificationToken.delete({ where: { token } });
  }

  async saveRefreshToken(userId: string, token: string): Promise<void> {
    const expiresAt = new Date();
    expiresAt.setDate(expiresAt.getDate() + 7); // 7 days

    const tokenHash = await hash(token, 12);

    await this.prisma.refreshToken.create({
      data: { userId, token: tokenHash, expiresAt },
    });
  }

  async validateRefreshToken(token: string) {
    const now = new Date();

    // Find all non-expired refresh tokens and compare hashes
    const activeTokens = await this.prisma.refreshToken.findMany({
      where: { expiresAt: { gt: now } },
      include: { user: true },
    });

    for (const rt of activeTokens) {
      const match = await compare(token, rt.token);
      if (match) {
        // Update last used
        await this.prisma.refreshToken.update({
          where: { id: rt.id },
          data: { lastUsed: new Date() },
        });

        return rt.user;
      }
    }

    return null;
  }

  async revokeRefreshToken(token: string): Promise<void> {
    const now = new Date();

    // Find all non-expired refresh tokens and compare hashes
    const activeTokens = await this.prisma.refreshToken.findMany({
      where: { expiresAt: { gt: now } },
    });

    for (const rt of activeTokens) {
      const match = await compare(token, rt.token);
      if (match) {
        await this.prisma.refreshToken.delete({ where: { id: rt.id } });
        return;
      }
    }
  }
}
