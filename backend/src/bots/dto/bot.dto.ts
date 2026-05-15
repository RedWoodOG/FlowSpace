import { IsString, IsOptional, IsBoolean, IsEnum, MaxLength, MinLength } from 'class-validator';

export class CreateBotDto {
  @IsString()
  @MinLength(1)
  @MaxLength(64)
  name: string;

  @IsString()
  @MinLength(1)
  @MaxLength(128)
  displayName: string;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  description?: string;

  @IsOptional()
  @IsString()
  avatarUrl?: string;
}

export class UpdateBotDto {
  @IsOptional()
  @IsString()
  @MinLength(1)
  @MaxLength(128)
  displayName?: string;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  description?: string;

  @IsOptional()
  @IsString()
  avatarUrl?: string;

  @IsOptional()
  @IsBoolean()
  active?: boolean;
}

export class CreateCommandDto {
  @IsString()
  @MinLength(1)
  @MaxLength(64)
  command: string;

  @IsString()
  @MaxLength(200)
  description: string;

  @IsOptional()
  @IsString()
  handlerType?: string;

  @IsOptional()
  @IsString()
  handlerUrl?: string;
}

export class UpdateCommandDto {
  @IsOptional()
  @IsString()
  @MaxLength(200)
  description?: string;

  @IsOptional()
  @IsBoolean()
  enabled?: boolean;

  @IsOptional()
  @IsString()
  handlerType?: string;

  @IsOptional()
  @IsString()
  handlerUrl?: string;
}

export class SubscribeEventDto {
  @IsString()
  @MinLength(1)
  @MaxLength(64)
  event: string;
}
