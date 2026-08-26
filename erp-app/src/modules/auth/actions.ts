"use server";

import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { mensajeError } from "@/lib/utils";
import { loginSchema, type LoginForm } from "./types";

export async function signOutAction(): Promise<void> {
  const supabase = await createClient();
  await supabase.auth.signOut();
  redirect("/login");
}

type ResultadoLogin =
  | { success: true; destino: string }
  | { success: false; error: string };

// No usa `redirect()`: el cliente necesita `router.refresh()` para que los
// Server Components vuelvan a leer la sesión que esta action acaba de cookiear.
export async function signInAction(input: LoginForm): Promise<ResultadoLogin> {
  const parsed = loginSchema.safeParse(input);
  if (!parsed.success) return { success: false, error: parsed.error.issues[0].message };

  const supabase = await createClient();
  const { error } = await supabase.auth.signInWithPassword({
    email: parsed.data.email,
    password: parsed.data.password,
  });

  if (error) return { success: false, error: mensajeError(error) };

  return { success: true, destino: parsed.data.next };
}
