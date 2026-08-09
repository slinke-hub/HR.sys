-- FIX FOR ADMIN UPDATING ROLES
-- This grants ADMIN users the permission to update any profile, enabling the role change feature.
-- It also allows users to update their own profiles (useful for future features like avatar uploads).

CREATE POLICY "Admins can update all profiles" ON profiles FOR UPDATE USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'ADMIN'));
CREATE POLICY "Users can update their own profile" ON profiles FOR UPDATE USING (auth.uid() = id);
