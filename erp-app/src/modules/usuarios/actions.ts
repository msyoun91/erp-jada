"use server";

import { createClient as createSupabaseClient } from "@supabase/supabase-js";
import { revalidatePath } from "next/cache";
import type { Database } from "@/lib/supabase/database.types";
import { puedeGestionarUsuarios } from "./permissions";
import {
  asignarSubmodulosSchema,
  crearUsuarioSchema,
  type AsignarSubmodulosForm,
  type CrearUsuarioForm,
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
    return { success: false as const, error: error.message };
  }

  revalidatePath("/usuarios");
  return { success: true as const };
}

export async function desactivarUsuario(usuarioId: string) {
  if (!(await puedeGestionarUsuarios())) {
    return { success: false as const, error: "No autorizado" };
  }

  const admin = createAdminClient();
  const { error } = await admin
    .from("usuarios")
    .update({ activo: false })
    .eq("id", usuarioId);

  if (error) {
    return { success: false as const, error: error.message };
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

  const admin = createAdminClient();
  const { usuario_id, submodulo_ids } = parsed.data;

  const { error: deactivateError } = await admin
    .from("usuario_submodulos")
    .update({ activo: false })
    .eq("usuario_id", usuario_id);

  if (deactivateError) {
    return { success: false as const, error: deactivateError.message };
  }

  if (submodulo_ids.length > 0) {
    const { error: upsertError } = await admin
      .from("usuario_submodulos")
      .upsert(
        submodulo_ids.map((submodulo_id) => ({
          usuario_id,
          submodulo_id,
          activo: true,
        })),
        { onConflict: "usuario_id,submodulo_id" }
      );

    if (upsertError) {
      return { success: false as const, error: upsertError.message };
    }
  }

  revalidatePath("/usuarios");
  return { success: true as const };
}
