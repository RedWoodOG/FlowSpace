import { ForbiddenException, Injectable, Logger } from '@nestjs/common';
import { promises as fs } from 'fs';
import * as path from 'path';
import * as os from 'os';

export interface WorkspaceDirectoryStructure {
  root: string;
  files: string;
  assets: string;
  shared: string;
  private: string;
}

@Injectable()
export class WorkspaceFilesystemService {
  private readonly logger = new Logger(WorkspaceFilesystemService.name);
  private readonly baseWorkspacePath: string;

  constructor() {
    // Base path: C:\Users\{user}\FlowSpace\Workspaces
    const homeDir = os.homedir();
    this.baseWorkspacePath = path.join(homeDir, 'FlowSpace', 'Workspaces');
  }

  /**
   * Get the base path for all workspaces
   */
  getBasePath(): string {
    return this.baseWorkspacePath;
  }

  /**
   * Get the full path for a specific workspace
   */
  getWorkspacePath(workspaceSlug: string): string {
    const resolved = path.resolve(this.baseWorkspacePath, workspaceSlug);
    if (!resolved.startsWith(path.resolve(this.baseWorkspacePath))) {
      throw new ForbiddenException('Invalid workspace path');
    }
    return resolved;
  }

  /**
   * Create a new workspace directory structure
   */
  async createWorkspaceDirectory(workspaceSlug: string, workspaceName: string): Promise<WorkspaceDirectoryStructure> {
    const workspaceRoot = this.getWorkspacePath(workspaceSlug);

    this.logger.log(`Creating workspace directory: ${workspaceRoot}`);

    // Create directory structure
    const structure: WorkspaceDirectoryStructure = {
      root: workspaceRoot,
      files: path.join(workspaceRoot, 'Files'),
      assets: path.join(workspaceRoot, 'Assets'),
      shared: path.join(workspaceRoot, 'Shared'),
      private: path.join(workspaceRoot, 'Private'),
    };

    try {
      // Create all directories
      await fs.mkdir(structure.root, { recursive: true });
      await fs.mkdir(structure.files, { recursive: true });
      await fs.mkdir(structure.assets, { recursive: true });
      await fs.mkdir(structure.shared, { recursive: true });
      await fs.mkdir(structure.private, { recursive: true });

      // Create .flowspace metadata file
      const metadata = {
        workspaceName,
        workspaceSlug,
        createdAt: new Date().toISOString(),
        version: '1.0.0',
      };

      await fs.writeFile(
        path.join(workspaceRoot, '.flowspace'),
        JSON.stringify(metadata, null, 2),
        'utf-8'
      );

      // Create README
      const readme = `# ${workspaceName}

This is your FlowSpace workspace directory.

## Structure

- **Files/**: General workspace files
- **Assets/**: Media, images, and other assets
- **Shared/**: Files shared with all workspace members
- **Private/**: Your private files (not synced to vault)

All files (except Private/) are automatically synced to the vault.
`;

      await fs.writeFile(
        path.join(workspaceRoot, 'README.md'),
        readme,
        'utf-8'
      );

      this.logger.log(`Workspace directory created successfully: ${workspaceRoot}`);

      return structure;
    } catch (error: any) {
      this.logger.error(`Failed to create workspace directory: ${error.message}`, error.stack);
      throw error;
    }
  }

  /**
   * Check if workspace directory exists
   */
  async workspaceDirectoryExists(workspaceSlug: string): Promise<boolean> {
    const workspacePath = this.getWorkspacePath(workspaceSlug);
    
    try {
      const stats = await fs.stat(workspacePath);
      return stats.isDirectory();
    } catch {
      return false;
    }
  }

  /**
   * Initialize workspace directory for existing workspace
   */
  async initializeWorkspaceDirectory(workspaceSlug: string, workspaceName: string): Promise<WorkspaceDirectoryStructure> {
    const exists = await this.workspaceDirectoryExists(workspaceSlug);
    
    if (exists) {
      this.logger.log(`Workspace directory already exists: ${workspaceSlug}`);
      return this.getWorkspaceStructure(workspaceSlug);
    }

    return this.createWorkspaceDirectory(workspaceSlug, workspaceName);
  }

  /**
   * Get workspace directory structure
   */
  getWorkspaceStructure(workspaceSlug: string): WorkspaceDirectoryStructure {
    const workspaceRoot = this.getWorkspacePath(workspaceSlug);

    return {
      root: workspaceRoot,
      files: path.join(workspaceRoot, 'Files'),
      assets: path.join(workspaceRoot, 'Assets'),
      shared: path.join(workspaceRoot, 'Shared'),
      private: path.join(workspaceRoot, 'Private'),
    };
  }

  /**
   * List all files in workspace directory (excluding Private/)
   */
  async listWorkspaceFiles(workspaceSlug: string): Promise<string[]> {
    const structure = this.getWorkspaceStructure(workspaceSlug);
    const files: string[] = [];

    const dirsToScan = [
      structure.files,
      structure.assets,
      structure.shared,
    ];

    for (const dir of dirsToScan) {
      try {
        const dirFiles = await this.listFilesRecursive(dir, dir);
        files.push(...dirFiles);
      } catch (error: any) {
        this.logger.warn(`Could not scan directory ${dir}: ${error.message}`);
      }
    }

    return files;
  }

  /**
   * Recursively list files in directory
   */
  private async listFilesRecursive(dirPath: string, basePath: string): Promise<string[]> {
    const files: string[] = [];

    try {
      const entries = await fs.readdir(dirPath, { withFileTypes: true });

      for (const entry of entries) {
        const fullPath = path.join(dirPath, entry.name);

        if (entry.isDirectory()) {
          const subFiles = await this.listFilesRecursive(fullPath, basePath);
          files.push(...subFiles);
        } else {
          // Return relative path from base
          const relativePath = path.relative(basePath, fullPath);
          files.push(relativePath);
        }
      }
    } catch (error: any) {
      this.logger.error(`Error listing files in ${dirPath}: ${error.message}`);
    }

    return files;
  }

  /**
   * Delete workspace directory
   */
  async deleteWorkspaceDirectory(workspaceSlug: string): Promise<void> {
    const workspacePath = this.getWorkspacePath(workspaceSlug);

    try {
      await fs.rm(workspacePath, { recursive: true, force: true });
      this.logger.log(`Workspace directory deleted: ${workspacePath}`);
    } catch (error: any) {
      this.logger.error(`Failed to delete workspace directory: ${error.message}`, error.stack);
      throw error;
    }
  }

  /**
   * Get workspace metadata from .flowspace file
   */
  async getWorkspaceMetadata(workspaceSlug: string): Promise<any> {
    const metadataPath = path.join(this.getWorkspacePath(workspaceSlug), '.flowspace');

    try {
      const content = await fs.readFile(metadataPath, 'utf-8');
      return JSON.parse(content);
    } catch (error: any) {
      this.logger.warn(`Could not read workspace metadata: ${error.message}`);
      return null;
    }
  }
}
