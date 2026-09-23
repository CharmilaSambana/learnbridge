import { createFileRoute } from "@tanstack/react-router";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { Check, Download, Eye, FileText, Folder, ShieldCheck, Trash2, UserCheck, Users, X } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { AppHeader } from "@/components/app-header";
import { Button } from "@/components/ui/button";
import { useAuth } from "@/lib/use-auth";

export const Route = createFileRoute("/_authenticated/admin")({ component: AdminPage });

type UserRow = {
  id: string;
  name: string;
  regulation: string | null;
  approved: boolean;
  created_at: string;
  roles: string[];
  logins: number;
};

type MaterialRow = {
  id: string;
  title: string;
  file_path: string;
  teacher_id: string;
  teacher_name: string;
  regulation: string;
  views: number;
  downloads: number;
};

type Dashboard = {
  users: UserRow[];
  materials: MaterialRow[];
};

function AdminPage() {
  const { user, role, loading } = useAuth();
  const queryClient = useQueryClient();

  const dashboard = useQuery({
    queryKey: ["admin-dashboard"],
    enabled: !!user && role === "admin",
    queryFn: async () => {
      const { data, error } = await supabase.rpc("admin_dashboard" as never);
      if (error) throw error;
      return data as Dashboard;
    },
  });

  const refresh = () => queryClient.invalidateQueries({ queryKey: ["admin-dashboard"] });

  const call = async (fn: string, args: Record<string, unknown>, success: string) => {
    const { error } = await supabase.rpc(fn as never, args as never);
    if (error) return toast.error(error.message);
    toast.success(success);
    refresh();
  };

  const removeMaterial = async (material: MaterialRow) => {
    if (!confirm(`Delete “${material.title}”? This cannot be undone.`)) return;
    const { data: path, error } = await supabase.rpc("admin_delete_material" as never, {
      target_material: material.id,
    } as never);
    if (error) return toast.error(error.message);
    if (path) await supabase.storage.from("materials").remove([path as string]);
    toast.success("PDF deleted successfully");
    refresh();
  };

  if (loading) return null;
  if (role !== "admin") {
    return (
      <div className="flex min-h-screen items-center justify-center p-10 text-center text-muted-foreground">
        Administrator access is required to view this portal.
      </div>
    );
  }

  const data = dashboard.data;
  const studentsCount = data?.users.filter((x) => x.roles.includes("student")).length ?? 0;
  const facultyCount = data?.users.filter((x) => x.roles.includes("teacher")).length ?? 0;
  const adminCount = data?.users.filter((x) => x.roles.includes("admin")).length ?? 0;
  const totalLogins = data?.users.reduce((acc, u) => acc + (u.logins || 0), 0) ?? 0;
  const totalViews = data?.materials.reduce((acc, m) => acc + (m.views || 0), 0) ?? 0;
  const totalDownloads = data?.materials.reduce((acc, m) => acc + (m.downloads || 0), 0) ?? 0;

  // Group faculty stats
  const facultySummaries = (data?.users.filter((u) => u.roles.includes("teacher")) ?? []).map((f) => {
    const teacherMaterials = (data?.materials ?? []).filter((m) => m.teacher_id === f.id);
    const pdfCount = teacherMaterials.length;
    const views = teacherMaterials.reduce((sum, m) => sum + (m.views || 0), 0);
    const downloads = teacherMaterials.reduce((sum, m) => sum + (m.downloads || 0), 0);
    return {
      id: f.id,
      name: f.name || "Unnamed Faculty",
      folder: `${f.id}/`,
      pdfCount,
      views,
      downloads,
    };
  });

  return (
    <div className="min-h-screen bg-background">
      <AppHeader
        title="Admin Control Center"
        subtitle="Approve user registrations, manage roles, audit faculty PDF folders, and monitor platform reach."
        badge="Admin"
      />

      <main className="mx-auto max-w-7xl space-y-8 px-6 py-10">
        {/* Metric Cards Grid */}
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          <Metric label="Total Registrations" value={data?.users.length ?? 0} sub={`${studentsCount} Students · ${facultyCount} Faculty · ${adminCount} Admins`} icon={<Users className="h-5 w-5 text-primary" />} />
          <Metric label="Total Platform Logins" value={totalLogins} sub="Across all approved users" icon={<UserCheck className="h-5 w-5 text-emerald-500" />} />
          <Metric label="PDFs Uploaded" value={data?.materials.length ?? 0} sub={`By ${facultyCount} faculty members`} icon={<FileText className="h-5 w-5 text-indigo-500" />} />
          <Metric label="Total Student Reach" value={totalViews + totalDownloads} sub={`${totalViews} Views · ${totalDownloads} Downloads`} icon={<Eye className="h-5 w-5 text-amber-500" />} />
        </div>

        {/* User Approvals & Role Management Table */}
        <section className="rounded-2xl border border-border bg-card p-6 shadow-[var(--shadow-card)]">
          <div className="flex items-center justify-between">
            <div>
              <h2 className="font-display text-lg font-semibold text-foreground">User Approvals & Role Management</h2>
              <p className="mt-1 text-sm text-muted-foreground">Students and faculty can only log in after an admin approves their registration.</p>
            </div>
            <span className="rounded-full bg-primary/10 px-3 py-1 text-xs font-semibold text-primary">
              {data?.users.filter((u) => !u.approved).length ?? 0} Pending
            </span>
          </div>

          <div className="mt-5 overflow-x-auto">
            <table className="w-full min-w-[780px] text-sm">
              <thead className="border-b border-border text-left text-xs font-semibold text-muted-foreground uppercase">
                <tr>
                  <th className="pb-3">User Details</th>
                  <th>Roles</th>
                  <th>Status</th>
                  <th>Logins</th>
                  <th className="text-right">Actions</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-border">
                {data?.users.map((person) => {
                  const isTeacherRole = person.roles.includes("teacher");
                  const isAdminRole = person.roles.includes("admin");
                  return (
                    <tr key={person.id} className="hover:bg-secondary/20 transition-colors">
                      <td className="py-4">
                        <p className="font-medium text-foreground">{person.name || "Unnamed User"}</p>
                        <p className="text-xs text-muted-foreground">{person.regulation ? `Regulation: ${person.regulation}` : "No regulation set"}</p>
                      </td>
                      <td>
                        <div className="flex flex-wrap gap-1">
                          {person.roles.map((r) => (
                            <span key={r} className={`rounded-full px-2.5 py-0.5 text-xs font-semibold ${r === "admin" ? "bg-amber-500/10 text-amber-600" : r === "teacher" ? "bg-indigo-500/10 text-indigo-600" : "bg-sky-500/10 text-sky-600"}`}>
                              {r === "teacher" ? "Faculty" : r}
                            </span>
                          ))}
                        </div>
                      </td>
                      <td>
                        {person.approved ? (
                          <span className="inline-flex items-center gap-1.5 rounded-full bg-emerald-500/10 px-2.5 py-0.5 text-xs font-medium text-emerald-600">
                            <Check className="h-3 w-3" /> Approved
                          </span>
                        ) : (
                          <span className="inline-flex items-center gap-1.5 rounded-full bg-amber-500/10 px-2.5 py-0.5 text-xs font-medium text-amber-600">
                            <X className="h-3 w-3" /> Pending Approval
                          </span>
                        )}
                      </td>
                      <td className="font-semibold text-foreground">{person.logins}</td>
                      <td className="py-3 text-right space-x-2">
                        <Button
                          size="sm"
                          variant={person.approved ? "outline" : "default"}
                          onClick={() => call("admin_set_approval", { target_user: person.id, approved: !person.approved }, person.approved ? "Approval revoked" : "User approved")}
                        >
                          {person.approved ? "Revoke" : "Approve"}
                        </Button>
                        <Button
                          size="sm"
                          variant="outline"
                          onClick={() => call("admin_set_primary_role", { target_user: person.id, new_role: isTeacherRole ? "student" : "teacher" }, `Role changed to ${isTeacherRole ? "Student" : "Faculty"}`)}
                        >
                          Make {isTeacherRole ? "Student" : "Faculty"}
                        </Button>
                        {!isAdminRole && (
                          <Button
                            size="sm"
                            variant="secondary"
                            onClick={() => call("admin_set_primary_role", { target_user: person.id, new_role: "admin" }, "Admin access granted")}
                          >
                            <ShieldCheck className="mr-1 h-3.5 w-3.5 text-amber-500" /> Make Admin
                          </Button>
                        )}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </section>

        {/* Faculty Folders Summary */}
        <section className="rounded-2xl border border-border bg-card p-6 shadow-[var(--shadow-card)]">
          <h2 className="font-display text-lg font-semibold text-foreground">Faculty PDF Folders Overview</h2>
          <p className="mt-1 text-sm text-muted-foreground">Every faculty member has a dedicated storage folder for their subject uploads.</p>
          <div className="mt-5 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
            {facultySummaries.length === 0 ? (
              <p className="col-span-full text-sm text-muted-foreground">No faculty members registered yet.</p>
            ) : (
              facultySummaries.map((f) => (
                <div key={f.id} className="rounded-xl border border-border bg-secondary/30 p-4">
                  <div className="flex items-center gap-2">
                    <Folder className="h-5 w-5 text-primary" />
                    <div>
                      <p className="font-medium text-foreground">{f.name}</p>
                      <p className="text-xs text-muted-foreground">Folder: <code className="rounded bg-muted px-1">{f.folder}</code></p>
                    </div>
                  </div>
                  <div className="mt-3 flex justify-between border-t border-border pt-3 text-xs text-muted-foreground">
                    <span>{f.pdfCount} PDFs</span>
                    <span>{f.views} Views</span>
                    <span>{f.downloads} Downloads</span>
                  </div>
                </div>
              ))
            )}
          </div>
        </section>

        {/* Faculty PDF Uploads & Reach Audit Table */}
        <section className="rounded-2xl border border-border bg-card p-6 shadow-[var(--shadow-card)]">
          <h2 className="font-display text-lg font-semibold text-foreground">Faculty PDF Reach & File Deletion</h2>
          <p className="mt-1 text-sm text-muted-foreground">Admins and respective faculty members have permission to delete files from storage.</p>
          <div className="mt-5 grid gap-3">
            {(data?.materials.length ?? 0) === 0 ? (
              <p className="rounded-xl border border-dashed border-border bg-secondary/20 p-8 text-center text-sm text-muted-foreground">No PDFs uploaded yet.</p>
            ) : (
              data?.materials.map((m) => (
                <div key={m.id} className="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-border bg-card p-4 transition-all hover:border-primary/30">
                  <div className="flex items-start gap-3">
                    <FileText className="mt-1 h-5 w-5 text-primary" />
                    <div>
                      <p className="font-medium text-foreground">{m.title}</p>
                      <p className="text-xs text-muted-foreground">Faculty: <span className="font-semibold text-foreground">{m.teacher_name}</span> · Regulation: {m.regulation} · Path: <code className="rounded bg-muted px-1">{m.file_path}</code></p>
                      <div className="mt-1.5 flex gap-4 text-xs text-muted-foreground">
                        <span className="inline-flex items-center gap-1 text-sky-600"><Eye className="h-3.5 w-3.5" /> {m.views} views</span>
                        <span className="inline-flex items-center gap-1 text-indigo-600"><Download className="h-3.5 w-3.5" /> {m.downloads} downloads</span>
                      </div>
                    </div>
                  </div>
                  <Button variant="destructive" size="sm" onClick={() => removeMaterial(m)}>
                    <Trash2 className="mr-1.5 h-4 w-4" /> Delete PDF
                  </Button>
                </div>
              ))
            )}
          </div>
        </section>
      </main>
    </div>
  );
}

function Metric({ label, value, sub, icon }: { label: string; value: number; sub: string; icon: React.ReactNode }) {
  return (
    <div className="rounded-2xl border border-border bg-card p-5 shadow-[var(--shadow-card)]">
      <div className="flex items-center justify-between">
        <span className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">{label}</span>
        {icon}
      </div>
      <p className="mt-2 font-display text-3xl font-bold text-foreground">{value}</p>
      <p className="mt-1 text-xs text-muted-foreground">{sub}</p>
    </div>
  );
}
