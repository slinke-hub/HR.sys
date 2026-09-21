export type AuthState = 'SIGNED_OUT' | 'SIGNED_IN' | 'TOKEN_REFRESHING' | 'EXPIRED' | 'DISABLED';

export interface AuthSessionDto {
  state: AuthState;
  userId?: string | null;
  accessToken?: string | null;
  expiresAt?: number | null;
  refreshable: boolean;
}

export interface AuthAdapter {
  signIn(credentials: { email: string; password: string }): Promise<AuthSessionDto>;
  getSession(): Promise<AuthSessionDto>;
  refreshSession(): Promise<AuthSessionDto>;
  signOut(): Promise<{ success: boolean; error?: unknown }>;
  requestPasswordReset(email: string): Promise<{ success: boolean; error?: unknown }>;
  onStateChange?(listener: (session: AuthSessionDto) => void): () => void;
}

// Supabase Auth owns token issuance and revocation. Native adapters must put
// the returned tokens in Keychain/Keystore-backed storage, never AsyncStorage.

