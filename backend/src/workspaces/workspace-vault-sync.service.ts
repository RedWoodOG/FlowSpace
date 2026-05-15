import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { S3Client, PutObjectCommand, GetObjectCommand, ListObjectsV2Command, DeleteObjectCommand } from '@aws-sdk/client-s3';
import { promises as fs } from 'fs';
import * as path from 'path';
import * as crypto from 'crypto';
import { WorkspaceFilesystemService } from './workspace-filesystem.service';

export interface SyncResult {
  uploaded: number;
  downloaded: number;
  deleted: number;
  errors: string[];
}

@Injectable()
export class WorkspaceVaultSyncService {
  private readonly logger = new Logger(WorkspaceVaultSyncService.name);
  private readonly s3Client: S3Client;
  private readonly bucket: string;

  constructor(
    private readonly configService: ConfigService,
    private readonly filesystemService: WorkspaceFilesystemService,
  ) {
    // Initialize S3/MinIO client
    const endpoint = this.configService.get<string>('MINIO_ENDPOINT', 'http://localhost:9000');
    const accessKey = this.configService.get<string>('MINIO_ACCESS_KEY');
    const secretKey = this.configService.get<string>('MINIO_SECRET_KEY');
    if (!accessKey || !secretKey) {
      throw new Error('MINIO_ACCESS_KEY and MINIO_SECRET_KEY must be configured');
    }
    this.bucket = this.configService.get<string>('MINIO_BUCKET', 'flowspace');

    this.s3Client = new S3Client({
      endpoint,
      region: 'us-east-1',
      credentials: {
        accessKeyId: accessKey,
        secretAccessKey: secretKey,
      },
      forcePathStyle: true,
    });
  }

  /**
   * Upload a file from workspace to vault
   */
  async uploadFileToVault(workspaceSlug: string, relativePath: string): Promise<void> {
    const structure = this.filesystemService.getWorkspaceStructure(workspaceSlug);
    
    // Determine which directory the file is in
    let localFilePath: string;
    if (relativePath.startsWith('Files/')) {
      localFilePath = path.join(structure.files, path.relative('Files', relativePath));
    } else if (relativePath.startsWith('Assets/')) {
      localFilePath = path.join(structure.assets, path.relative('Assets', relativePath));
    } else if (relativePath.startsWith('Shared/')) {
      localFilePath = path.join(structure.shared, path.relative('Shared', relativePath));
    } else {
      throw new Error(`Invalid file path: ${relativePath}`);
    }

    try {
      // Read file
      const fileContent = await fs.readFile(localFilePath);
      
      // S3 key format: workspaces/{workspaceSlug}/{relativePath}
      const s3Key = `workspaces/${workspaceSlug}/${relativePath}`;

      // Upload to S3/MinIO
      await this.s3Client.send(new PutObjectCommand({
        Bucket: this.bucket,
        Key: s3Key,
        Body: fileContent,
      }));

      this.logger.log(`Uploaded file to vault: ${s3Key}`);
    } catch (error: any) {
      this.logger.error(`Failed to upload file ${relativePath}: ${error.message}`, error.stack);
      throw error;
    }
  }

  /**
   * Download a file from vault to workspace
   */
  async downloadFileFromVault(workspaceSlug: string, relativePath: string): Promise<void> {
    const structure = this.filesystemService.getWorkspaceStructure(workspaceSlug);
    
    // Determine local path
    let localFilePath: string;
    if (relativePath.startsWith('Files/')) {
      localFilePath = path.join(structure.files, path.relative('Files', relativePath));
    } else if (relativePath.startsWith('Assets/')) {
      localFilePath = path.join(structure.assets, path.relative('Assets', relativePath));
    } else if (relativePath.startsWith('Shared/')) {
      localFilePath = path.join(structure.shared, path.relative('Shared', relativePath));
    } else {
      throw new Error(`Invalid file path: ${relativePath}`);
    }

    try {
      // S3 key
      const s3Key = `workspaces/${workspaceSlug}/${relativePath}`;

      // Download from S3/MinIO
      const response = await this.s3Client.send(new GetObjectCommand({
        Bucket: this.bucket,
        Key: s3Key,
      }));

      // Get file content
      const chunks: Uint8Array[] = [];
      for await (const chunk of response.Body as any) {
        chunks.push(chunk);
      }
      const fileContent = Buffer.concat(chunks);

      // Ensure directory exists
      await fs.mkdir(path.dirname(localFilePath), { recursive: true });

      // Write file
      await fs.writeFile(localFilePath, fileContent);

      this.logger.log(`Downloaded file from vault: ${s3Key}`);
    } catch (error: any) {
      this.logger.error(`Failed to download file ${relativePath}: ${error.message}`, error.stack);
      throw error;
    }
  }

  /**
   * Sync all workspace files to vault
   */
  async syncWorkspaceToVault(workspaceSlug: string): Promise<SyncResult> {
    const result: SyncResult = {
      uploaded: 0,
      downloaded: 0,
      deleted: 0,
      errors: [],
    };

    try {
      // Get all local files
      const localFiles = await this.filesystemService.listWorkspaceFiles(workspaceSlug);

      this.logger.log(`Syncing ${localFiles.length} files to vault for workspace: ${workspaceSlug}`);

      // Upload each file
      for (const file of localFiles) {
        try {
          await this.uploadFileToVault(workspaceSlug, file);
          result.uploaded++;
        } catch (error: any) {
          result.errors.push(`Failed to upload ${file}: ${error.message}`);
        }
      }

      this.logger.log(`Sync to vault completed: ${result.uploaded} uploaded, ${result.errors.length} errors`);
    } catch (error: any) {
      this.logger.error(`Failed to sync workspace to vault: ${error.message}`, error.stack);
      result.errors.push(`Sync failed: ${error.message}`);
    }

    return result;
  }

  /**
   * Sync vault files to local workspace
   */
  async syncVaultToWorkspace(workspaceSlug: string): Promise<SyncResult> {
    const result: SyncResult = {
      uploaded: 0,
      downloaded: 0,
      deleted: 0,
      errors: [],
    };

    try {
      // List all files in vault for this workspace
      const prefix = `workspaces/${workspaceSlug}/`;
      const vaultFiles = await this.listVaultFiles(prefix);

      this.logger.log(`Syncing ${vaultFiles.length} files from vault to workspace: ${workspaceSlug}`);

      // Download each file
      for (const s3Key of vaultFiles) {
        try {
          // Get relative path (remove prefix)
          const relativePath = s3Key.replace(prefix, '');
          await this.downloadFileFromVault(workspaceSlug, relativePath);
          result.downloaded++;
        } catch (error: any) {
          result.errors.push(`Failed to download ${s3Key}: ${error.message}`);
        }
      }

      this.logger.log(`Sync from vault completed: ${result.downloaded} downloaded, ${result.errors.length} errors`);
    } catch (error: any) {
      this.logger.error(`Failed to sync vault to workspace: ${error.message}`, error.stack);
      result.errors.push(`Sync failed: ${error.message}`);
    }

    return result;
  }

  /**
   * Two-way sync between workspace and vault
   */
  async bidirectionalSync(workspaceSlug: string): Promise<SyncResult> {
    // First, sync vault to local (download any new files)
    const downloadResult = await this.syncVaultToWorkspace(workspaceSlug);
    
    // Then, sync local to vault (upload any new/changed files)
    const uploadResult = await this.syncWorkspaceToVault(workspaceSlug);

    return {
      uploaded: uploadResult.uploaded,
      downloaded: downloadResult.downloaded,
      deleted: 0,
      errors: [...downloadResult.errors, ...uploadResult.errors],
    };
  }

  /**
   * List all files in vault for a workspace
   */
  private async listVaultFiles(prefix: string): Promise<string[]> {
    const files: string[] = [];

    try {
      let continuationToken: string | undefined;

      do {
        const response = await this.s3Client.send(new ListObjectsV2Command({
          Bucket: this.bucket,
          Prefix: prefix,
          ContinuationToken: continuationToken,
        }));

        if (response.Contents) {
          for (const object of response.Contents) {
            if (object.Key && !object.Key.endsWith('/')) {
              files.push(object.Key);
            }
          }
        }

        continuationToken = response.NextContinuationToken;
      } while (continuationToken);
    } catch (error: any) {
      this.logger.error(`Failed to list vault files: ${error.message}`, error.stack);
    }

    return files;
  }

  /**
   * Delete workspace files from vault
   */
  async deleteWorkspaceFromVault(workspaceSlug: string): Promise<void> {
    const prefix = `workspaces/${workspaceSlug}/`;
    const files = await this.listVaultFiles(prefix);

    this.logger.log(`Deleting ${files.length} files from vault for workspace: ${workspaceSlug}`);

    for (const s3Key of files) {
      try {
        await this.s3Client.send(new DeleteObjectCommand({
          Bucket: this.bucket,
          Key: s3Key,
        }));
      } catch (error: any) {
        this.logger.error(`Failed to delete file ${s3Key}: ${error.message}`);
      }
    }

    this.logger.log(`Workspace files deleted from vault: ${workspaceSlug}`);
  }

  /**
   * Check if file exists in vault
   */
  async fileExistsInVault(workspaceSlug: string, relativePath: string): Promise<boolean> {
    const s3Key = `workspaces/${workspaceSlug}/${relativePath}`;

    try {
      await this.s3Client.send(new GetObjectCommand({
        Bucket: this.bucket,
        Key: s3Key,
      }));
      return true;
    } catch {
      return false;
    }
  }
}
