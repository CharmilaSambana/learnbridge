import { createFileRoute, Outlet, redirect } from "@tanstack/react-router";
import { supabase } from "@/integrations/supabase/client";

export const Route = createFileRoute("/_authenticated")({
  ssr: false,
  beforeLoad: async () => {
    const { data, error } = await supabase.auth.getUser();
    if (error || !data.user) throw redirect({ to: "/auth", search: { role: "student" } });

    const [{ data: profile }, { data: roleRows }] = await Promise.all([
      supabase.from("profiles").select("is_approved").eq("id", data.user.id).maybeSingle(),
      supabase.from("user_roles").select("role").eq("user_id", data.user.id),
    ]);

    const roles = (roleRows ?? []).map((r) => r.role);
    const isAdmin = roles.includes("admin");
    const userRole = isAdmin ? "admin" : roles.includes("teacher") ? "teacher" : "student";

    const isApproved = profile?.is_approved || isAdmin;

    if (!isApproved) {
      await supabase.auth.signOut();
      throw redirect({ to: "/auth", search: { role: userRole as "student" | "teacher" | "admin", pending: "1" } });
    }
    return { user: data.user, role: userRole };
  },
  component: () => <Outlet />,
});
