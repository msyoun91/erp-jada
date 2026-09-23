"use server";

import { createClient as createSupabaseClient } from "@supabase/supabase-js";
import { revalidatePath } from "next/cache";
import type { Database } from "@/lib/supabase/database.types";
import { createClient } from "@/lib/supabase/server";
import { mensajeError } from "@/lib/utils";
import { puedeGestionarUsuarios } from "./permissions";
import {
  asignarSubmodulosSchema,
  crearUsuarioSchema,
  editarUsuarioSchema,
  resetearPasswordSchema,
  type AsignarSubmodulosForm,
  type CrearUsuarioForm,
  type EditarUsuarioForm,
  type ResetearPasswordForm,
} from "./types";

function createAdminClient() {
  return createSupabaseClient<Database>(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.SUPABASE_SERVICE_ROLE_KEY!
  );
}

export async function crearUsuario(input: CrearUsuarioForm) {
  if (!(await puedeGestionarUsuarios())) {
    return { success: false as const, error: "No autorizado" };
  }

  const parsed = crearUsuarioSchema.safeParse(input);
  if (!parsed.success) {
    return { success: false as const, error: parsed.error.issues[0].message };
  }

  const admin = createAdminClient();
  const { error } = await admin.auth.admin.createUser({
    email: parsed.data.email,
    password: parsed.data.password,
    email_confirm: true,
    user_metadata: { nombre: parsed.data.nombre },
  });

  if (error) {
    return { success: false as const, error: mensajeError(error) };
  }

  revalidatePath("/usuarios");
  return { success: true as const };
}

export async function editarUsuario(input: EditarUsuarioForm) {
  if (!(await puedeGestionarUsuarios())) {
    return { success: false as const, error: "No autorizado" };
  }

  const parsed = editarUsuarioSchema.safeParse(input);
  if (!parsed.success) {
    return { success: false as const, error: parsed.error.issues[0].message };
  }

  const admin = createAdminClient();
  const { id, nombre, email } = parsed.data;

  const { data: actual, error: leerError } = await admin
    .from("usuarios")
    .select("email")
    .eq("id", id)
    .single();

  if (leerError) {
    return { success: false as const, error: mensajeError(leerError) };
  }

  // El email es la credencial: se cambia en `auth.users` y el trigger de
  // `sql/021` lo baja a `usuarios`. Escribirlo también acá sería una segunda
  // copia de la misma verdad. Solo se toca auth si cambió — editar el nombre
  // no tiene por qué pasar por el servicio de auth.
  if (actual.email !== email) {
    const { error: authError } = await admin.auth.admin.updateUserById(id, {
      email,
      email_confirm: true,
    });

    if (authError) {
      return { success: false as const, error: mensajeError(authError) };
    }
  }

  const { error } = await admin.from("usuarios").update({ nombre }).eq("id", id);

  if (error) {
    return { success: false as const, error: mensajeError(error) };
  }

  revalidatePath("/usuarios");
  return { success: true as const };
}

export async function resetearPassword(input: ResetearPasswordForm) {
  if (!(await puedeGestionarUsuarios())) {
    return { success: false as const, error: "No autorizado" };
  }

  const parsed = resetearPasswordSchema.safeParse(input);
  if (!parsed.success) {
    return { success: false as const, error: parsed.error.issues[0].message };
  }

  const admin = createAdminClient();
  const { error } = await admin.auth.admin.updateUserById(parsed.data.id, {
    password: parsed.data.password,
  });

  if (error) {
    return { success: false as const, error: mensajeError(error) };
  }

  return { success: true as const };
}

// Supabase no tiene ban permanente: 100 años es el equivalente práctico.
// Reactivar lo levanta con `ban_duration: "none"`.
const BAN_INDEFINIDO = "876000h";

export async function desactivarUsuario(usuarioId: string) {
  if (!(await puedeGestionarUsuarios())) {
    return { success: false as const, error: "No autorizado" };
  }

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  // Sin esta guarda el único gestor puede dejar el sistema sin nadie que
  // pueda reactivar a nadie — incluido él.
  if (user?.id === usuarioId) {
    return { success: false as const, error: "No podés desactivar tu propia cuenta" };
  }

  const admin = createAdminClient();
  const { error } = await admin
    .from("usuarios")
    .update({ activo: false })
    .eq("id", usuarioId);

  if (error) {
    return { success: false as const, error: mensajeError(error) };
  }

  // `activo = false` le saca los permisos (`tiene_permiso`, `sql/020`) y el
  // proxy lo echa del ERP, pero su access token sigue siendo válido hasta que
  // expire: sin el ban entra igual por la API con lo que RLS le concede por
  // `auth.uid()`. El ban además rechaza el login nuevo.
  const { error: banError } = await admin.auth.admin.updateUserById(usuarioId, {
    ban_duration: BAN_INDEFINIDO,
  });

  if (banError) {
    await admin.from("usuarios").update({ activo: true }).eq("id", usuarioId);
    return { success: false as const, error: mensajeError(banError) };
  }

  revalidatePath("/usuarios");
  return { success: true as const };
}

export async function reactivarUsuario(usuarioId: string) {
  if (!(await puedeGestionarUsuarios())) {
    return { success: false as const, error: "No autorizado" };
  }

  const admin = createAdminClient();
  const { error } = await admin
    .from("usuarios")
    .update({ activo: true })
    .eq("id", usuarioId);

  if (error) {
    // `idx_usuarios_email_activo` es parcial (WHERE activo): mientras estuvo
    // desactivado, ese email pudo darse de alta en otra cuenta.
    if ((error as { code?: string }).code === "23505") {
      return {
        success: false as const,
        error: "Ya hay un usuario activo con ese email",
      };
    }
    return { success: false as const, error: mensajeError(error) };
  }

  const { error: banError } = await admin.auth.admin.updateUserById(usuarioId, {
    ban_duration: "none",
  });

  if (banError) {
    await admin.from("usuarios").update({ activo: false }).eq("id", usuarioId);
    return { success: false as const, error: mensajeError(banError) };
  }

  revalidatePath("/usuarios");
  return { success: true as const };
}

export async function asignarSubmodulos(input: AsignarSubmodulosForm) {
  if (!(await puedeGestionarUsuarios())) {
    return { success: false as const, error: "No autorizado" };
  }

  const parsed = asignarSubmodulosSchema.safeParse(input);
  if (!parsed.success) {
    return { success: false as const, error: parsed.error.issues[0].message };
  }

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return { success: false as const, error: "No autorizado" };
  }

  // Con `service_role` no hay `auth.uid()`: el admin se pasa explícito para
  // que quede en `otorgada_por`. Vista/función, techo y cascadas los valida la
  // base (`sql/105`).
  const { error } = await createAdminClient().rpc("asignar_submodulos", {
    p_admin: user.id,
    p_usuario: parsed.data.usuario_id,
    p_submodulos: parsed.data.submodulo_ids,
  });

  if (error) {
    return { success: false as const, error: mensajeError(error) };
  }

  revalidatePath("/usuarios");
  return { success: true as const };
}
