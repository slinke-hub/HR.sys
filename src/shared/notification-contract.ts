import type { Notification } from './domain-types';

export type NotificationTargetType = 'TASK' | 'PROJECT' | 'DEAL' | 'CLIENT' | 'REQUEST' | 'DOCUMENT' | 'APPROVAL';

export interface NotificationTarget {
  type: NotificationTargetType;
  id: string;
  view?: 'tasks' | 'projects' | 'crm' | 'clients' | 'requests' | 'documents' | null;
}

export interface DeviceRegistration {
  id?: string;
  platform: 'ios' | 'android' | 'web';
  push_token?: string | null;
  endpoint?: string | null;
  p256dh?: string | null;
  auth_key?: string | null;
  device_name?: string | null;
  app_version?: string | null;
}

export interface NotificationListQuery {
  limit?: number;
  before?: string | null;
  unreadOnly?: boolean;
}

export interface NotificationDto extends Notification {
  target?: NotificationTarget | null;
  read_at?: string | null;
}

export interface NotificationAdapter {
  registerDevice(device: DeviceRegistration): Promise<{ success: boolean; data?: unknown; error?: unknown }>;
  unregisterDevice(deviceId: string): Promise<{ success: boolean; error?: unknown }>;
  updateDeviceToken(deviceId: string, pushToken: string): Promise<{ success: boolean; error?: unknown }>;
  list(query?: NotificationListQuery): Promise<NotificationDto[]>;
  get(notificationId: string): Promise<NotificationDto | null>;
  unreadCount(): Promise<number>;
  markRead(notificationId: string): Promise<{ success: boolean; error?: unknown }>;
  markAllRead(): Promise<{ success: boolean; count?: number; error?: unknown }>;
  delete(notificationId: string): Promise<{ success: boolean; error?: unknown }>;
}
