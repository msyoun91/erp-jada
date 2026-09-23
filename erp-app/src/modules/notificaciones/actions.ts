"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { mensajeError } from "@/lib/utils";
import { uuidSchema } from "./types";

// Sin chequeo de permisos y con el cliente normal: la RLS de
// `usuario_notificaciones` es `usuario_id = auth.uid()` y el GRANT es por
// columna (`leida_at`, `activo`), así que la base ya acota qué fila y qué campo
// —mismo criterio que el toggle de widgets.

export async function marcarLeida(id: string) {
  const parsed = uuidSchema.safeParse(id);
  if (!parsed.success) return { success: false as const, error: "Notificación inválida" };

  const supabase = await createClient();
  const { error } = await supabase
    .from("usuario_notificaciones")
    .update({ leida_at: new Date().toISOString() })
    .eq("id", parsed.data)
    .is("leida_at", null);

  if (error) return { success: false as const, error: mensajeError(error) };

  revalidatePath("/", "layout");
  return { success: true as const };
}

export async function marcarTodasLeidas() {
  const supabase = await createClient();
  const { error } = await supabase
    .from("usuario_notificaciones")
    .update({ leida_at: new Date().toISOString() })
    .is("leida_at", null);

  if (error) return { success: false as const, error: mensajeError(error) };

  revalidatePath("/", "layout");
  return { success: true as const };
}
