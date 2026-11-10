"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { mensajeError } from "@/lib/utils";
import { altaSchema, type AltaForm } from "./types";

// Quién puede armar en esa obra lo decide `presupuestos_alta`: acá solo se valida la forma y se traduce el error.
export async function crearPresupuesto(input: AltaForm) {
  const parsed = altaSchema.safeParse(input);
  if (!parsed.success) return { success: false as const, error: parsed.error.issues[0].message };
  const d = parsed.data;
  const supabase = await createClient();
  const { data: id, error } = await supabase.rpc("presupuestos_alta", {
    p_obra: d.obra,
    p_nombre: d.nombre,
    p_moneda: d.moneda,
    p_alicuota: d.alicuota,
    ...(d.seccion ? { p_seccion: d.seccion } : {}),
  });
  if (error) return { success: false as const, error: mensajeError(error) };
  revalidatePath("/presupuestos", "layout");
  return { success: true as const, id };
}
