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
