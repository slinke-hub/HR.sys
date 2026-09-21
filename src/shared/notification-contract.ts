import type { Notification } from './domain-types';

export type NotificationTargetType = 'TASK' | 'PROJECT' | 'DEAL' | 'CLIENT' | 'REQUEST' | 'DOCUMENT';

export interface NotificationTarget {
  type: NotificationTargetType;
  id: string;
  route?: string | null;
}

export interface DeviceRegistration {
  id?: string;
  platform: 'ios' | 'android' | 'web';
  push_token: string;
  device_name?: string | null;
  app_version?: string | null;
}

export interface NotificationDto extends Notification {
  target?: NotificationTarget | null;
  read_at?: string | null;
}

export interface NotificationAdapter {
  registerDevice(device: DeviceRegistration): Promise<{ success: boolean; data?: unknown; error?: unknown }>;
  unregisterDevice(deviceId: string): Promise<{ success: boolean; error?: unknown }>;
  list(userId: string): Promise<NotificationDto[]>;
  markRead(notificationId: string): Promise<{ success: boolean; error?: unknown }>;
}

