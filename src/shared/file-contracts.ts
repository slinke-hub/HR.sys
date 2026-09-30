/** Safe file contracts for web and native adapters. The backend must enforce
 * these limits again; this module is only a shared request/response shape. */
export type AttachmentOwner = 'TASK' | 'COMMENT' | 'DEAL' | 'PROJECT' | 'CLIENT';

export interface UploadFileRequest {
  owner_type: AttachmentOwner;
  owner_id: string;
  file_name: string;
  mime_type: string;
  size_bytes: number;
  description?: string | null;
}

export interface StoredFileReference {
  id?: string;
  owner_type: AttachmentOwner;
  owner_id: string;
  storage_reference: string;
  file_name: string;
  mime_type?: string | null;
  size_bytes?: number | null;
  is_archived?: boolean;
  visible_to_project_assignee?: boolean;
  created_at?: string;
}

/** The backend, not a native client, authorizes each operation. */
export type FileOperation =
  | 'list'
  | 'view'
  | 'download'
  | 'upload'
  | 'archive'
  | 'remove';

export const ALLOWED_UPLOAD_MIME_TYPES = Object.freeze([
  'application/pdf',
  'image/jpeg',
  'image/png',
  'image/webp',
  'text/plain',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
]);

export const MAX_UPLOAD_BYTES = 25 * 1024 * 1024;
