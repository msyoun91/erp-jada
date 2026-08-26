"use server";

import { createClient as createSupabaseClient } from "@supabase/supabase-js";
import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { mensajeError } from "@/lib/utils";
import {
  cambiarPasswordSchema,
  loginSchema,
  perfilSchema,
  type CambiarPasswordForm,
  type LoginForm,
  type PerfilForm,
} from "./types";

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

const SESION_VENCIDA = "Tu sesión venció. Volvé a ingresar.";

export async function actualizarNombre(input: PerfilForm) {
  const parsed = perfilSchema.safeParse(input);
  if (!parsed.success) return { success: false as const, error: parsed.error.issues[0].message };

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return { success: false as const, error: SESION_VENCIDA };

  // Cliente normal, no `service_role`: quién puede tocar esta fila lo decide
  // `usuarios_update_propio` (`sql/022`), y el GRANT por columna es lo que
  // impide que "editar mi perfil" llegue hasta `activo`.
  const { error } = await supabase
    .from("usuarios")
    .update({ nombre: parsed.data.nombre })
    .eq("id", user.id);

  if (error) return { success: false as const, error: mensajeError(error) };

  // El nombre se muestra en el footer del sidebar, que vive en el layout.
  revalidatePath("/", "layout");
  return { success: true as const };
}

export async function cambiarPassword(input: CambiarPasswordForm) {
  const parsed = cambiarPasswordSchema.safeParse(input);
  if (!parsed.success) return { success: false as const, error: parsed.error.issues[0].message };

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user?.email) return { success: false as const, error: SESION_VENCIDA };

  // Con la sesión abierta, `updateUser` cambiaría la contraseña sin pedir la
  // anterior: quien se sienta frente a una máquina desbloqueada se queda con
  // la cuenta. La verificación va en un cliente sin cookies — hacer
  // `signInWithPassword` sobre el cliente de servidor rotaría, de paso, la
  // sesión que el usuario está usando.
  const verificador = createSupabaseClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
  );

  const { error: credencialesError } = await verificador.auth.signInWithPassword({
    email: user.email,
    password: parsed.data.passwordActual,
  });

  if (credencialesError) {
    return { success: false as const, error: "La contraseña actual no es correcta" };
  }

  const { error } = await supabase.auth.updateUser({ password: parsed.data.password });
  if (error) return { success: false as const, error: mensajeError(error) };

  return { success: true as const };
}
