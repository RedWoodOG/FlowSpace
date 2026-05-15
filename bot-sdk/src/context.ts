import type { Bot } from './bot';

export interface CommandPayload {
  command: string;
  args: string;
  channelId: string;
  userId: string;
  userName: string;
  messageId: string;
  timestamp: string;
}

export class CommandContext {
  readonly command: string;
  readonly args: string;
  readonly channelId: string;
  readonly userId: string;
  readonly userName: string;
  readonly messageId: string;
  readonly timestamp: string;

  private readonly bot: Bot;

  constructor(bot: Bot, payload: CommandPayload) {
    this.bot = bot;
    this.command = payload.command;
    this.args = payload.args;
    this.channelId = payload.channelId;
    this.userId = payload.userId;
    this.userName = payload.userName;
    this.messageId = payload.messageId;
    this.timestamp = payload.timestamp;
  }

  async reply(content: string, attachments?: string[]): Promise<void> {
    await this.bot.sendMessage(this.channelId, content, attachments);
  }
}
