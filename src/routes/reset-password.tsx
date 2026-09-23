import { createFileRoute, Link, useNavigate } from "@tanstack/react-router";
import { useState } from "react";
import { Eye, EyeOff } from "lucide-react";
import { toast } from "sonner";
import { supabase } from "@/integrations/supabase/client";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";

export const Route = createFileRoute("/reset-password")({ component: ResetPasswordPage });

function ResetPasswordPage() {
  const navigate = useNavigate();
  const [visible, setVisible] = useState(false);
  const [saving, setSaving] = useState(false);
  async function submit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const password = String(new FormData(event.currentTarget).get("password") ?? "");
    if (password.length < 6) return toast.error("Password must be at least 6 characters");
    setSaving(true);
    const { error } = await supabase.auth.updateUser({ password });
    setSaving(false);
    if (error) return toast.error("This reset link is invalid or has expired. Request a new one.");
    toast.success("Password changed. You can now sign in.");
    await supabase.auth.signOut();
    navigate({ to: "/auth", search: { role: "student" }, replace: true });
  }
  return <div className="flex min-h-screen items-center justify-center bg-background px-4"><form onSubmit={submit} className="w-full max-w-md rounded-2xl border border-border bg-card p-7 shadow-[var(--shadow-card)]"><h1 className="font-display text-2xl font-semibold">Set a new password</h1><p className="mt-2 text-sm text-muted-foreground">Choose a secure password with at least 6 characters.</p><div className="mt-6 space-y-2"><Label htmlFor="new-password">New password</Label><div className="relative"><Input id="new-password" name="password" type={visible ? "text" : "password"} minLength={6} required className="pr-10" autoComplete="new-password" /><button type="button" onClick={() => setVisible(!visible)} aria-label={visible ? "Hide password" : "Show password"} className="absolute inset-y-0 right-0 flex w-10 items-center justify-center text-muted-foreground hover:text-foreground">{visible ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}</button></div></div><Button type="submit" className="mt-6 w-full" disabled={saving}>{saving ? "Saving…" : "Update password"}</Button><Link to="/auth" search={{ role: "student" }} className="mt-4 block text-center text-sm font-medium text-primary hover:underline">Back to sign in</Link></form></div>;
}
