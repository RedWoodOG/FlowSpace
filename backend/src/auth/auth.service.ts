import { Injectable, UnauthorizedException, ConflictException, BadRequestException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { PrismaService } from '../database/prisma.service';
import { AuthTokenPayload, AuthUser } from './jwt-payload.interface';
import { compare, hash } from 'bcrypt';
import { sign, verify } from 'jsonwebtoken';
import { TokenService } from './services/token.service';
import { EmailService } from './services/email.service';

@Injectable()
export class AuthService {
  private readonly tokenTtl = '12h';

  constructor(
    private readonly prisma: PrismaService,
    private readonly config: ConfigService,
    private readonly tokenService: TokenService,
    private readonly emailService: EmailService,
  ) {}

  private get jwtSecret(): string {
    const secret = this.config.get<string>('JWT_SECRET');
    if (!secret) {
      throw new Error('JWT_SECRET is not configured');
    }
    return secret;
  }

  private sanitizeUser(user: {
    id: string;
    email: string;
    displayName: string | null;
    nickname?: string | null;
    passwordHash: string;
  }): AuthUser {
    return {
      id: user.id,
      email: user.email,
      displayName: user.displayName,
      nickname: user.nickname || undefined,
    };
  }

  async validateUser(email: string, password: string): Promise<AuthUser> {
    const user = await this.prisma.user.findUnique({ where: { email } });
    if (!user) {
      throw new UnauthorizedException('Invalid credentials');
    }

    const valid = await compare(password, user.passwordHash);
    if (!valid) {
      throw new UnauthorizedException('Invalid credentials');
    }

    return this.sanitizeUser(user);
  }

  issueToken(user: AuthUser): { token: string } {
    const payload: AuthTokenPayload = {
      sub: user.id,
      email: user.email,
      displayName: user.displayName,
    };

    const token = sign(payload, this.jwtSecret, { expiresIn: this.tokenTtl, algorithm: 'HS256' as const });
    return { token };
  }

  async register(
    email: string,
    password: string,
    name: string,
    nickname?: string,
  ): Promise<{
    token: string;
    user: AuthUser;
  }> {
    // Check if user already exists
    const existingUser = await this.prisma.user.findUnique({
      where: { email },
    });

    if (existingUser) {
      throw new ConflictException('User with this email already exists');
    }

    // Validate input
    if (!email || !password || !name) {
      throw new BadRequestException('Email, password, and name are required');
    }

    // Validate email format (basic check)
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    if (!emailRegex.test(email)) {
      throw new BadRequestException('Invalid email format');
    }

    // Validate password length
    if (password.length < 8) {
      throw new BadRequestException('Password must be at least 8 characters long');
    }

    const passwordHash = await hash(password, 12);

    // Create the user in Prisma
    const newUser = await this.prisma.user.create({
      data: {
        email,
        passwordHash,
        displayName: name,
        nickname: nickname || null,
      },
    });

    // Create AuthUser object
    const authUser: AuthUser = {
      id: newUser.id,
      email: newUser.email,
      displayName: newUser.displayName,
      nickname: newUser.nickname || undefined,
    };

    // Issue token (same format as login)
    const { token } = this.issueToken(authUser);

    return { token, user: authUser };
  }

  async login(email: string, password: string): Promise<{
    token: string;
    user: AuthUser;
  }> {
    const user = await this.validateUser(email, password);
    const { token } = this.issueToken(user);
    return { token, user };
  }

  verifyToken(token: string): AuthTokenPayload {
    try {
      const decoded = verify(token, this.jwtSecret, { algorithms: ['HS256'] });
      if (typeof decoded === 'string') {
        throw new UnauthorizedException('Invalid token');
      }
      return decoded as AuthTokenPayload;
    } catch (error) {
      throw new UnauthorizedException('Invalid token');
    }
  }

  // NEW: Register with email verification
  async registerWithVerification(
    email: string,
    password: string,
    name: string,
    nickname?: string,
  ): Promise<{
    message: string;
    userId: string;
  }> {
    // Check if user already exists — return uniform message to prevent email enumeration
    const existingUser = await this.prisma.user.findUnique({ where: { email } });
    if (existingUser) {
      return { message: 'If this email is eligible, a verification message will be sent.', userId: 'pending' };
    }

    // Validate email format
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    if (!emailRegex.test(email)) {
      throw new BadRequestException('Invalid email format');
    }

    // Validate password length
    if (password.length < 8) {
      throw new BadRequestException('Password must be at least 8 characters long');
    }

    const passwordHash = await hash(password, 12);

    const newUser = await this.prisma.user.create({
      data: {
        email,
        passwordHash,
        displayName: name,
        nickname: nickname || null,
        emailVerified: false,
      },
    });

    // Generate and save verification token
    const verificationToken = this.tokenService.generateVerificationToken();
    await this.tokenService.saveVerificationToken(newUser.id, verificationToken);

    // Send verification email
    await this.emailService.sendVerificationEmail(email, name, verificationToken);

    return {
      message: 'Registration successful. Please check your email to verify your account.',
      userId: newUser.id,
    };
  }

  // NEW: Verify email with token
  async verifyEmail(token: string): Promise<{ message: string }> {
    const verificationToken = await this.tokenService.validateVerificationToken(token);

    if (!verificationToken) {
      throw new BadRequestException('Invalid or expired verification token');
    }

    await this.prisma.user.update({
      where: { id: verificationToken.userId },
      data: { emailVerified: true },
    });

    await this.tokenService.deleteVerificationToken(token);

    return { message: 'Email verified successfully' };
  }

  // NEW: Login with remember me
  async loginWithRememberMe(
    email: string,
    password: string,
    rememberMe: boolean = false,
  ): Promise<{
    token: string;
    refreshToken?: string;
    user: AuthUser;
  }> {
    const user = await this.validateUser(email, password);

    // Check if email is verified
    const dbUser = await this.prisma.user.findUnique({ where: { id: user.id } });
    if (!dbUser?.emailVerified) {
      throw new UnauthorizedException('Please verify your email before logging in');
    }

    const { token } = this.issueToken(user);

    let refreshToken: string | undefined;
    if (rememberMe) {
      refreshToken = this.tokenService.generateRefreshToken();
      await this.tokenService.saveRefreshToken(user.id, refreshToken);
    }

    return { token, refreshToken, user };
  }

  // NEW: Refresh access token
  async refreshAccessToken(refreshToken: string): Promise<{ token: string }> {
    const user = await this.tokenService.validateRefreshToken(refreshToken);

    if (!user) {
      throw new UnauthorizedException('Invalid or expired refresh token');
    }

    const authUser: AuthUser = {
      id: user.id,
      email: user.email,
      displayName: user.displayName,
      nickname: user.nickname || undefined,
    };

    return this.issueToken(authUser);
  }
}
