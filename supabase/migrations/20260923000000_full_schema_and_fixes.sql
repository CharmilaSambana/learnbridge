-- ScholarShare Full Database Schema, Security Policies, Triggers & RPC Functions
-- Run this in your Supabase SQL Editor to initialize or fix your backend database.

-- 1. App Roles Enum
DO $$ BEGIN
  CREATE TYPE public.app_role AS ENUM ('student', 'teacher', 'admin');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;
ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'admin';

-- 2. Profiles Table
CREATE TABLE IF NOT EXISTS public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name TEXT NOT NULL DEFAULT '',
  regulation TEXT,
  is_approved BOOLEAN NOT NULL DEFAULT false,
  approved_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS is_approved BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS approved_at TIMESTAMPTZ;

GRANT SELECT, INSERT, UPDATE ON public.profiles TO authenticated;
GRANT ALL ON public.profiles TO service_role;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- 3. User Roles Table
CREATE TABLE IF NOT EXISTS public.user_roles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role public.app_role NOT NULL,
  UNIQUE (user_id, role)
);

GRANT SELECT ON public.user_roles TO authenticated;
GRANT ALL ON public.user_roles TO service_role;
ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;

-- 4. Login Events Table
CREATE TABLE IF NOT EXISTS public.login_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_login_events_user ON public.login_events(user_id);
GRANT SELECT, INSERT ON public.login_events TO authenticated;
GRANT ALL ON public.login_events TO service_role;
ALTER TABLE public.login_events ENABLE ROW LEVEL SECURITY;

-- 5. Subjects Table
CREATE TABLE IF NOT EXISTS public.subjects (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  teacher_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  code TEXT NOT NULL DEFAULT '',
  regulation TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.subjects TO authenticated;
GRANT ALL ON public.subjects TO service_role;
ALTER TABLE public.subjects ENABLE ROW LEVEL SECURITY;

-- 6. Materials (PDFs) Table
CREATE TABLE IF NOT EXISTS public.materials (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  teacher_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  subject_id UUID NOT NULL REFERENCES public.subjects(id) ON DELETE CASCADE,
  regulation TEXT NOT NULL,
  title TEXT NOT NULL,
  file_path TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_materials_reg ON public.materials(regulation);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.materials TO authenticated;
GRANT ALL ON public.materials TO service_role;
ALTER TABLE public.materials ENABLE ROW LEVEL SECURITY;

-- 7. Material Events (Views & Downloads Reach Tracking)
CREATE TABLE IF NOT EXISTS public.material_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  material_id UUID NOT NULL REFERENCES public.materials(id) ON DELETE CASCADE,
  student_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  event_type TEXT NOT NULL CHECK (event_type IN ('view','download')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (material_id, student_id, event_type)
);

CREATE INDEX IF NOT EXISTS idx_events_material ON public.material_events(material_id);
GRANT SELECT, INSERT ON public.material_events TO authenticated;
GRANT ALL ON public.material_events TO service_role;
ALTER TABLE public.material_events ENABLE ROW LEVEL SECURITY;

-- 8. Helper Functions
CREATE OR REPLACE FUNCTION public.has_role(_user_id uuid, _role public.app_role)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = _user_id AND role = _role);
$$;

CREATE OR REPLACE FUNCTION public.is_admin(_user_id uuid DEFAULT auth.uid())
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = _user_id AND role = 'admin'::public.app_role);
$$;

REVOKE ALL ON FUNCTION public.has_role(uuid, public.app_role) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.has_role(uuid, public.app_role) TO authenticated;
REVOKE ALL ON FUNCTION public.is_admin(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_admin(uuid) TO authenticated;

-- 9. Trigger for New User Registration
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  requested_role text;
  is_admin_user boolean;
BEGIN
  requested_role := COALESCE(NEW.raw_user_meta_data->>'role', 'student');
  is_admin_user := (requested_role = 'admin');

  INSERT INTO public.profiles (id, full_name, is_approved, approved_at)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'full_name', ''),
    is_admin_user,
    CASE WHEN is_admin_user THEN now() ELSE NULL END
  )
  ON CONFLICT (id) DO NOTHING;

  IF requested_role = 'admin' THEN
    INSERT INTO public.user_roles (user_id, role) VALUES (NEW.id, 'admin'::public.app_role) ON CONFLICT DO NOTHING;
  ELSIF requested_role = 'teacher' THEN
    INSERT INTO public.user_roles (user_id, role) VALUES (NEW.id, 'teacher'::public.app_role) ON CONFLICT DO NOTHING;
  ELSE
    INSERT INTO public.user_roles (user_id, role) VALUES (NEW.id, 'student'::public.app_role) ON CONFLICT DO NOTHING;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
AFTER INSERT ON auth.users
FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- 10. Record Login RPC Function
CREATE OR REPLACE FUNCTION public.record_login()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.is_admin() AND NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND is_approved) THEN
    RAISE EXCEPTION 'Your account is awaiting administrator approval';
  END IF;
  INSERT INTO public.login_events(user_id) VALUES (auth.uid());
END;
$$;

REVOKE ALL ON FUNCTION public.record_login() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.record_login() TO authenticated;

-- 11. Admin Dashboard RPC Function
CREATE OR REPLACE FUNCTION public.admin_dashboard()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT CASE WHEN public.is_admin() THEN jsonb_build_object(
    'users', COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'id', p.id,
      'name', p.full_name,
      'regulation', p.regulation,
      'approved', p.is_approved,
      'created_at', p.created_at,
      'roles', COALESCE((SELECT jsonb_agg(ur.role::text) FROM public.user_roles ur WHERE ur.user_id = p.id), '[]'::jsonb),
      'logins', (SELECT count(*) FROM public.login_events le WHERE le.user_id = p.id)
    ) ORDER BY p.created_at DESC) FROM public.profiles p), '[]'::jsonb),
    'materials', COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'id', m.id,
      'title', m.title,
      'file_path', m.file_path,
      'teacher_id', m.teacher_id,
      'teacher_name', p.full_name,
      'regulation', m.regulation,
      'views', (SELECT count(*) FROM public.material_events e WHERE e.material_id = m.id AND e.event_type = 'view'),
      'downloads', (SELECT count(*) FROM public.material_events e WHERE e.material_id = m.id AND e.event_type = 'download')
    ) ORDER BY m.created_at DESC) FROM public.materials m JOIN public.profiles p ON p.id = m.teacher_id), '[]'::jsonb)
  ) ELSE NULL END;
$$;

REVOKE ALL ON FUNCTION public.admin_dashboard() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_dashboard() TO authenticated;

-- 12. Admin RPC Management Functions
CREATE OR REPLACE FUNCTION public.admin_set_approval(target_user uuid, approved boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin only'; END IF;
  UPDATE public.profiles
  SET is_approved = approved,
      approved_at = CASE WHEN approved THEN now() ELSE NULL END
  WHERE id = target_user;
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

-- 13. Row Level Security Policies
-- Profiles RLS
DROP POLICY IF EXISTS "own profile readable" ON public.profiles;
DROP POLICY IF EXISTS "teacher profiles readable" ON public.profiles;
DROP POLICY IF EXISTS "admins read profiles" ON public.profiles;
DROP POLICY IF EXISTS "admins update profiles" ON public.profiles;
DROP POLICY IF EXISTS "own profile insert" ON public.profiles;
DROP POLICY IF EXISTS "own profile update" ON public.profiles;

CREATE POLICY "own profile readable" ON public.profiles FOR SELECT TO authenticated USING (auth.uid() = id);
CREATE POLICY "teacher profiles readable" ON public.profiles FOR SELECT TO authenticated USING (public.has_role(id, 'teacher'::app_role));
CREATE POLICY "admins read profiles" ON public.profiles FOR SELECT TO authenticated USING (public.is_admin());
CREATE POLICY "own profile insert" ON public.profiles FOR INSERT TO authenticated WITH CHECK (auth.uid() = id);
CREATE POLICY "own profile update" ON public.profiles FOR UPDATE TO authenticated USING (auth.uid() = id) WITH CHECK (auth.uid() = id);
CREATE POLICY "admins update profiles" ON public.profiles FOR UPDATE TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

-- User Roles RLS
DROP POLICY IF EXISTS "read own roles" ON public.user_roles;
DROP POLICY IF EXISTS "admins read roles" ON public.user_roles;
DROP POLICY IF EXISTS "admins manage roles" ON public.user_roles;

CREATE POLICY "read own roles" ON public.user_roles FOR SELECT TO authenticated USING (auth.uid() = user_id);
CREATE POLICY "admins read roles" ON public.user_roles FOR SELECT TO authenticated USING (public.is_admin());
CREATE POLICY "admins manage roles" ON public.user_roles FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

-- Login Events RLS
DROP POLICY IF EXISTS "users record own logins" ON public.login_events;
DROP POLICY IF EXISTS "admins read login events" ON public.login_events;

CREATE POLICY "users record own logins" ON public.login_events FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
CREATE POLICY "admins read login events" ON public.login_events FOR SELECT TO authenticated USING (public.is_admin());

-- Subjects RLS
DROP POLICY IF EXISTS "subjects readable by authenticated" ON public.subjects;
DROP POLICY IF EXISTS "teacher manages own subjects" ON public.subjects;

CREATE POLICY "subjects readable by authenticated" ON public.subjects FOR SELECT TO authenticated USING (true);
CREATE POLICY "teacher manages own subjects" ON public.subjects FOR ALL TO authenticated
  USING (auth.uid() = teacher_id) WITH CHECK (auth.uid() = teacher_id AND public.has_role(auth.uid(), 'teacher'::app_role));

-- Materials RLS
DROP POLICY IF EXISTS "materials readable by authenticated" ON public.materials;
DROP POLICY IF EXISTS "teacher manages own materials" ON public.materials;
DROP POLICY IF EXISTS "admins delete material records" ON public.materials;

CREATE POLICY "materials readable by authenticated" ON public.materials FOR SELECT TO authenticated USING (true);
CREATE POLICY "teacher manages own materials" ON public.materials FOR ALL TO authenticated
  USING (auth.uid() = teacher_id) WITH CHECK (auth.uid() = teacher_id AND public.has_role(auth.uid(), 'teacher'::app_role));
CREATE POLICY "admins delete material records" ON public.materials FOR DELETE TO authenticated USING (public.is_admin());

-- Material Events RLS
DROP POLICY IF EXISTS "student inserts own events" ON public.material_events;
DROP POLICY IF EXISTS "student reads own events" ON public.material_events;
DROP POLICY IF EXISTS "teacher reads events on own materials" ON public.material_events;

CREATE POLICY "student inserts own events" ON public.material_events FOR INSERT TO authenticated WITH CHECK (auth.uid() = student_id);
CREATE POLICY "student reads own events" ON public.material_events FOR SELECT TO authenticated USING (auth.uid() = student_id);
CREATE POLICY "teacher reads events on own materials" ON public.material_events FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.materials m WHERE m.id = material_id AND m.teacher_id = auth.uid()));

-- 14. Storage Bucket Policies (Materials Bucket)
-- Ensure 'materials' bucket exists in storage
INSERT INTO storage.buckets (id, name, public) VALUES ('materials', 'materials', false) ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "materials readable by owner or matching student" ON storage.objects;
DROP POLICY IF EXISTS "teacher uploads own materials files" ON storage.objects;
DROP POLICY IF EXISTS "teacher updates own materials files" ON storage.objects;
DROP POLICY IF EXISTS "teacher deletes own materials files" ON storage.objects;
DROP POLICY IF EXISTS "admins delete material objects" ON storage.objects;

CREATE POLICY "materials readable by owner or matching student" ON storage.objects FOR SELECT TO authenticated
USING (
  bucket_id = 'materials'
  AND EXISTS (
    SELECT 1 FROM public.materials m
    WHERE m.file_path = storage.objects.name
      AND (
        m.teacher_id = auth.uid()
        OR public.is_admin()
        OR EXISTS (
          SELECT 1 FROM public.profiles p
          WHERE p.id = auth.uid() AND p.regulation = m.regulation
        )
      )
  )
);

CREATE POLICY "teacher uploads own materials files" ON storage.objects FOR INSERT TO authenticated
WITH CHECK (bucket_id = 'materials' AND (storage.foldername(name))[1] = auth.uid()::text AND public.has_role(auth.uid(), 'teacher'::app_role));

CREATE POLICY "teacher updates own materials files" ON storage.objects FOR UPDATE TO authenticated
USING (bucket_id = 'materials' AND (storage.foldername(name))[1] = auth.uid()::text);

CREATE POLICY "teacher deletes own materials files" ON storage.objects FOR DELETE TO authenticated
USING (bucket_id = 'materials' AND (storage.foldername(name))[1] = auth.uid()::text);

CREATE POLICY "admins delete material objects" ON storage.objects FOR DELETE TO authenticated
USING (bucket_id = 'materials' AND public.is_admin());
