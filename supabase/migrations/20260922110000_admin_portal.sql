-- Administration, approval, and audit features for ScholarShare.
ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'admin';

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS is_approved boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS approved_at timestamptz;

-- Existing accounts are preserved.  An administrator can approve them from the portal.
CREATE TABLE IF NOT EXISTS public.login_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_login_events_user ON public.login_events(user_id);

ALTER TABLE public.login_events ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT ON public.login_events TO authenticated;
CREATE POLICY "users record own logins" ON public.login_events FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = user_id);

-- Centralized role check avoids exposing other users' role rows to regular users.
CREATE OR REPLACE FUNCTION public.is_admin(_user_id uuid DEFAULT auth.uid())
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = _user_id AND role = 'admin'::public.app_role)
$$;
REVOKE ALL ON FUNCTION public.is_admin(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_admin(uuid) TO authenticated;

CREATE POLICY "admins read profiles" ON public.profiles FOR SELECT TO authenticated USING (public.is_admin());
CREATE POLICY "admins update profiles" ON public.profiles FOR UPDATE TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());
CREATE POLICY "admins read roles" ON public.user_roles FOR SELECT TO authenticated USING (public.is_admin());
CREATE POLICY "admins manage roles" ON public.user_roles FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());
CREATE POLICY "admins read login events" ON public.login_events FOR SELECT TO authenticated USING (public.is_admin());

CREATE OR REPLACE FUNCTION public.record_login()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND is_approved) THEN
    RAISE EXCEPTION 'Your account is awaiting administrator approval';
  END IF;
  INSERT INTO public.login_events(user_id) VALUES (auth.uid());
END;
$$;
REVOKE ALL ON FUNCTION public.record_login() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.record_login() TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_dashboard()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT CASE WHEN public.is_admin() THEN jsonb_build_object(
    'users', COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'id', p.id, 'name', p.full_name, 'regulation', p.regulation,
      'approved', p.is_approved, 'created_at', p.created_at,
      'roles', COALESCE((SELECT jsonb_agg(ur.role::text) FROM public.user_roles ur WHERE ur.user_id = p.id), '[]'::jsonb),
      'logins', (SELECT count(*) FROM public.login_events le WHERE le.user_id = p.id)
    ) ORDER BY p.created_at DESC) FROM public.profiles p), '[]'::jsonb),
    'materials', COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'id', m.id, 'title', m.title, 'file_path', m.file_path, 'teacher_id', m.teacher_id,
      'teacher_name', p.full_name, 'regulation', m.regulation,
      'views', (SELECT count(*) FROM public.material_events e WHERE e.material_id = m.id AND e.event_type = 'view'),
      'downloads', (SELECT count(*) FROM public.material_events e WHERE e.material_id = m.id AND e.event_type = 'download')
    ) ORDER BY m.created_at DESC) FROM public.materials m JOIN public.profiles p ON p.id = m.teacher_id), '[]'::jsonb)
  ) ELSE NULL END
$$;
REVOKE ALL ON FUNCTION public.admin_dashboard() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_dashboard() TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_set_approval(target_user uuid, approved boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin only'; END IF;
  UPDATE public.profiles SET is_approved = approved, approved_at = CASE WHEN approved THEN now() ELSE NULL END WHERE id = target_user;
END; $$;

CREATE OR REPLACE FUNCTION public.admin_set_primary_role(target_user uuid, new_role public.app_role)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin only'; END IF;
  IF target_user = auth.uid() AND new_role <> 'admin' THEN RAISE EXCEPTION 'You cannot remove your own admin access'; END IF;
  DELETE FROM public.user_roles WHERE user_id = target_user AND role IN ('student'::public.app_role, 'teacher'::public.app_role);
  IF new_role IN ('student'::public.app_role, 'teacher'::public.app_role) THEN
    INSERT INTO public.user_roles(user_id, role) VALUES (target_user, new_role);
  ELSIF NOT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = target_user AND role = 'admin'::public.app_role) THEN
    INSERT INTO public.user_roles(user_id, role) VALUES (target_user, 'admin'::public.app_role);
  END IF;
END; $$;

CREATE OR REPLACE FUNCTION public.admin_delete_material(target_material uuid)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE object_path text;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin only'; END IF;
  SELECT file_path INTO object_path FROM public.materials WHERE id = target_material;
  IF object_path IS NULL THEN RAISE EXCEPTION 'Material not found'; END IF;
  DELETE FROM public.materials WHERE id = target_material;
  RETURN object_path;
END; $$;
REVOKE ALL ON FUNCTION public.admin_set_approval(uuid, boolean), public.admin_set_primary_role(uuid, public.app_role), public.admin_delete_material(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_set_approval(uuid, boolean), public.admin_set_primary_role(uuid, public.app_role), public.admin_delete_material(uuid) TO authenticated;

CREATE POLICY "admins delete material records" ON public.materials FOR DELETE TO authenticated USING (public.is_admin());
CREATE POLICY "admins delete material objects" ON storage.objects FOR DELETE TO authenticated USING (bucket_id = 'materials' AND public.is_admin());
