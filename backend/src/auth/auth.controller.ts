import { Body, Controller, Post, Get, Query, BadRequestException, UseGuards, Req } from '@nestjs/common';
import { IsEmail, IsString, IsOptional, MinLength } from 'class-validator';
import { Request } from 'express';
import { AuthService } from './auth.service';
import { JwtAuthGuard } from './jwt.guard';
import { TokenService } from './services/token.service';

export class RegisterDto {
  @IsEmail()
  email!: string;

  @MinLength(8)
  password!: string;

  @IsString()
  @MinLength(1)
  name!: string;

  @IsOptional()
  @IsString()
  nickname?: string;
}

export class LoginDto {
  @IsEmail()
  email!: string;

  @IsString()
  password!: string;
}

export class RefreshDto {
  @IsString()
  refreshToken!: string;
}

export class LogoutDto {
  @IsOptional()
  @IsString()
  refreshToken?: string;
}

@Controller('auth')
export class AuthController {
  constructor(
    private readonly authService: AuthService,
    private readonly tokenService: TokenService,
  ) {}

  @Post('register')
  async register(@Body() body: RegisterDto) {
    if (!body.email || !body.password || !body.name) {
      throw new BadRequestException('Email, password, and name are required');
    }

    return this.authService.register(body.email, body.password, body.name, body.nickname);
  }

  @Post('login')
  async login(@Body() body: LoginDto) {
    if (!body.email || !body.password) {
      throw new BadRequestException('Email and password are required');
    }

    return this.authService.login(body.email, body.password);
  }

  // NEW ENDPOINTS:

  @Post('register-with-verification')
  async registerWithVerification(@Body() body: RegisterDto) {
    if (!body.email || !body.password || !body.name) {
      throw new BadRequestException('Email, password, and name are required');
    }

    return this.authService.registerWithVerification(
      body.email,
      body.password,
      body.name,
      body.nickname,
    );
  }

  @Get('verify-email')
  async verifyEmail(@Query('token') token: string) {
    if (!token) {
      throw new BadRequestException('Token is required');
    }

    return this.authService.verifyEmail(token);
  }

  @Post('login-with-remember-me')
  async loginWithRememberMe(@Body() body: { email?: string; password?: string; rememberMe?: boolean }) {
    if (!body.email || !body.password) {
      throw new BadRequestException('Email and password are required');
    }

    return this.authService.loginWithRememberMe(
      body.email,
      body.password,
      body.rememberMe || false,
    );
  }

  @Post('refresh')
  async refresh(@Body() body: RefreshDto) {
    if (!body.refreshToken) {
      throw new BadRequestException('Refresh token is required');
    }

    return this.authService.refreshAccessToken(body.refreshToken);
  }

  @Post('logout')
  @UseGuards(JwtAuthGuard)
  async logout(@Body() body: LogoutDto, @Req() req: Request & { user?: { id: string } }) {
    if (body.refreshToken) {
      // Verify refresh token ownership before revoking
      const tokenOwner = await this.tokenService.validateRefreshToken(body.refreshToken);
      if (!tokenOwner || tokenOwner.id !== req.user?.id) {
        throw new BadRequestException('Refresh token does not belong to this user');
      }

      await this.tokenService.revokeRefreshToken(body.refreshToken);
    }

    return { message: 'Logged out successfully' };
  }
}
