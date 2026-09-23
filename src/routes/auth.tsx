import { createFileRoute, Link, useNavigate } from "@tanstack/react-router";
import { useEffect, useState } from "react";
import { toast } from "sonner";
import { z } from "zod";
import { ArrowLeft, Eye, EyeOff, GraduationCap, Presentation, ShieldCheck } from "lucide-react";

import { supabase } from "@/integrations/supabase/client";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";

const searchSchema = z.object({
  role: z.enum(["student", "teacher", "admin"]).catch("student"),
  pending: z.string().optional(),
});

export const Route = createFileRoute("/auth")({
  validateSearch: searchSchema,
  head: () => ({
    meta: [
      { title: "Sign in or register — ScholarShare" },
      {
        name: "description",
        content: "Create your student or faculty account, or sign in to access shared course PDFs.",
      },
      { property: "og:title", content: "Sign in or register — ScholarShare" },
      {
        property: "og:description",
        content: "Student and faculty accounts for the ScholarShare course PDF portal.",
      },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary_large_image" },
    ],
  }),
  component: AuthPage,
});

const credentials = z.object({
  email: z.string().trim().email("Enter a valid email").max(255),
  password: z.string().min(6, "Password must be at least 6 characters").max(72),
});

function AuthPage() {
  const { role, pending } = Route.useSearch();
  const navigate = useNavigate();
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    supabase.auth.getSession().then(async ({ data }) => {
      if (data.session) await routeByRole(navigate, role);
    });
  }, [navigate, role]);

  useEffect(() => {
    if (pending) toast.info("Your account is waiting for administrator approval.");
  }, [pending]);

  async function handleRegister(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    const form = new FormData(e.currentTarget);
    const fullName = String(form.get("fullName") ?? "").trim();
    const parsed = credentials.safeParse({
      email: form.get("email"),
      password: form.get("password"),
    });
    if (!fullName) return toast.error("Please enter your full name");
    if (!parsed.success) return toast.error(parsed.error.issues[0].message);

    setLoading(true);
    const { error } = await supabase.auth.signUp({
      email: parsed.data.email,
      password: parsed.data.password,
      options: {
        emailRedirectTo: window.location.origin,
        data: { full_name: fullName, role },
      },
    });
    setLoading(false);

    if (error) return toast.error(error.message);
    await supabase.auth.signOut();
    toast.success("Registration received. An administrator must approve your account before you can sign in.");
  }

  async function handleLogin(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    const form = new FormData(e.currentTarget);
    const parsed = credentials.safeParse({
      email: form.get("email"),
      password: form.get("password"),
    });
    if (!parsed.success) return toast.error(parsed.error.issues[0].message);

    setLoading(true);
    const { error } = await supabase.auth.signInWithPassword(parsed.data);
    if (error) {
      setLoading(false);
      return toast.error(error.message);
    }

    const { error: approvalError } = await supabase.rpc("record_login" as never);
    if (approvalError) {
      await supabase.auth.signOut();
      setLoading(false);
      return toast.info("Your account is waiting for administrator approval.");
    }

    const isAuthorized = await routeByRole(navigate, role);
    setLoading(false);
    if (isAuthorized) {
      toast.success("Welcome back");
    } else {
      toast.info("Your account is waiting for administrator approval.");
    }
  }

  async function handleForgotPassword() {
    const email = (document.getElementById("login-email") as HTMLInputElement | null)?.value.trim();
    if (!email || !z.string().email().safeParse(email).success) {
      return toast.error("Enter your email address first");
    }
    setLoading(true);
    const { error } = await supabase.auth.resetPasswordForEmail(email, {
      redirectTo: `${window.location.origin}/reset-password`,
    });
    setLoading(false);
    if (error) return toast.error(error.message);
    toast.success("Password reset email sent. Check your inbox.");
  }

  const isTeacher = role === "teacher";
  const isAdmin = role === "admin";

  return (
    <div className="flex min-h-screen items-center justify-center bg-background px-4 py-12">
      <div className="w-full max-w-md">
        <Link
          to="/"
          className="mb-6 inline-flex items-center gap-2 text-sm text-muted-foreground transition-colors hover:text-foreground"
        >
          <ArrowLeft className="h-4 w-4" /> Change role
        </Link>

        <div className="rounded-2xl border border-border bg-card p-7 shadow-[var(--shadow-card)]">
          <div className="flex items-center gap-3">
            <span className="flex h-11 w-11 items-center justify-center rounded-xl bg-primary/10 text-primary">
              {isAdmin ? (
                <ShieldCheck className="h-5 w-5" />
              ) : isTeacher ? (
                <Presentation className="h-5 w-5" />
              ) : (
                <GraduationCap className="h-5 w-5" />
              )}
            </span>
            <div>
              <h1 className="font-display text-xl font-semibold text-foreground">
                {isAdmin ? "Administrator access" : isTeacher ? "Faculty access" : "Student access"}
              </h1>
              <p className="text-sm text-muted-foreground">
                {isAdmin ? "Sign in with an administrator account." : "Register if you're new, otherwise sign in."}
              </p>
            </div>
          </div>

          <Tabs defaultValue="login" className="mt-6">
            <TabsList className={`grid w-full ${isAdmin ? "grid-cols-1" : "grid-cols-2"}`}>
              <TabsTrigger value="login">Login</TabsTrigger>
              {!isAdmin && <TabsTrigger value="register">Register</TabsTrigger>}
            </TabsList>

            <TabsContent value="login">
              <form onSubmit={handleLogin} className="space-y-4 pt-4">
                <Field id="login-email" name="email" label="Email" type="email" />
                <PasswordField id="login-password" name="password" label="Password" />
                <button
                  type="button"
                  onClick={handleForgotPassword}
                  disabled={loading}
                  className="text-sm font-medium text-primary hover:underline"
                >
                  Forgot password?
                </button>
                <Button type="submit" className="w-full" disabled={loading}>
                  {loading ? "Please wait…" : "Sign in"}
                </Button>
              </form>
            </TabsContent>

            {!isAdmin && (
              <TabsContent value="register">
                <form onSubmit={handleRegister} className="space-y-4 pt-4">
                  <Field id="reg-name" name="fullName" label="Full name" type="text" />
                  <Field id="reg-email" name="email" label="Email" type="email" />
                  <PasswordField id="reg-password" name="password" label="Password" />
                  <Button type="submit" className="w-full" disabled={loading}>
                    {loading ? "Please wait…" : `Create ${isTeacher ? "faculty" : "student"} account`}
                  </Button>
                </form>
              </TabsContent>
            )}
          </Tabs>
        </div>
      </div>
    </div>
  );
}

function Field({
  id,
  name,
  label,
  type,
}: {
  id: string;
  name: string;
  label: string;
  type: string;
}) {
  return (
    <div className="space-y-2">
      <Label htmlFor={id}>{label}</Label>
      <Input id={id} name={name} type={type} required maxLength={255} autoComplete="on" />
    </div>
  );
}

async function routeByRole(navigate: ReturnType<typeof useNavigate>, currentRole?: "student" | "teacher" | "admin") {
  const { data: userData } = await supabase.auth.getUser();
  if (!userData.user) return false;

  const [{ data: roleRows }, { data: profile }] = await Promise.all([
    supabase.from("user_roles").select("role").eq("user_id", userData.user.id),
    supabase.from("profiles").select("is_approved").eq("id", userData.user.id).maybeSingle(),
  ]);

  const roles = (roleRows ?? []).map((row) => row.role as string);
  const isAdmin = roles.includes("admin");
  const isTeacher = roles.includes("teacher");
  const detectedRole = isAdmin ? "admin" : isTeacher ? "teacher" : "student";
  const userRole = currentRole || detectedRole;

  // Admins are always approved by definition
  const isApproved = profile?.is_approved || isAdmin;

  if (!isApproved) {
    await supabase.auth.signOut();
    navigate({
      to: "/auth",
      search: { role: userRole as "student" | "teacher" | "admin", pending: "1" },
      replace: true,
    });
    return false;
  }

  const target = isAdmin ? "/admin" : isTeacher ? "/teacher" : "/student";
  navigate({ to: target, replace: true });
  return true;
}

function PasswordField({ id, name, label }: { id: string; name: string; label: string }) {
  const [visible, setVisible] = useState(false);
  return (
    <div className="space-y-2">
      <Label htmlFor={id}>{label}</Label>
      <div className="relative">
        <Input
          id={id}
          name={name}
          type={visible ? "text" : "password"}
          required
          maxLength={255}
          autoComplete="current-password"
          className="pr-10"
        />
        <button
          type="button"
          onClick={() => setVisible(!visible)}
          aria-label={visible ? "Hide password" : "Show password"}
          className="absolute inset-y-0 right-0 flex w-10 items-center justify-center text-muted-foreground hover:text-foreground"
        >
          {visible ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
        </button>
      </div>
    </div>
  );
}
