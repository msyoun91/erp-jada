"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { getUsuarioActualId } from "@/lib/usuarios";
import { mensajeError } from "@/lib/utils";
import { idSchema } from "@/lib/validacion";
import { consultarMonedapi } from "./monedapi";
import { corregirSchema, principalSchema, type CorregirForm, type PrincipalForm } from "./types";

// Quién puede qué lo deciden las funciones de `sql/156`: acá solo se valida la
// forma, se llama y se traduce el error. Los tipos de cambio están en la barra de
// menú de todas las pantallas: se revalida el layout raíz.

function fallo(error: unknown) {
  return { success: false as const, error: mensajeError(error) };
}

function invalido(issues: { message: string }[]) {
  return { success: false as const, error: issues[0].message };
}

function listo() {
  revalidatePath("/", "layout");
  return { success: true as const };
}

// MO002: cambia 50 % o más contra el vigente. La UI pregunta y reintenta con `confirmar_rojo`.
export async function corregirTipoCambio(input: CorregirForm) {
  const parsed = corregirSchema.safeParse(input);
  if (!parsed.success) return invalido(parsed.error.issues);
  const supabase = await createClient();
  const { error } = await supabase.rpc("monedas_corregir", {
    p_moneda: parsed.data.moneda,
    p_valor: parsed.data.valor,
    p_confirmar_rojo: parsed.data.confirmar_rojo,
  });
  if (error?.code === "MO002") return { ...fallo(error), pideConfirmar: true as const };
  return error ? fallo(error) : listo();
}

export async function confirmarTipoCambio(id: unknown) {
  const parsed = idSchema.safeParse(id);
  if (!parsed.success) return invalido(parsed.error.issues);
  const supabase = await createClient();
  const { error } = await supabase.rpc("monedas_confirmar", { p_id: parsed.data });
  return error ? fallo(error) : listo();
}

export async function elegirPrincipal(input: PrincipalForm) {
  const parsed = principalSchema.safeParse(input);
  if (!parsed.success) return invalido(parsed.error.issues);
  const supabase = await createClient();
  const { error } = await supabase.rpc("monedas_elegir_principal", { p_moneda: parsed.data.moneda });
  return error ? fallo(error) : listo();
}

// El botón de la barra: cualquier usuario con sesión. El tope de uno por minuto lo
// pone la base, así que tocarlo de más no le pega a MonedAPI.
export async function actualizarTiposCambio() {
  if (!(await getUsuarioActualId())) return { success: false as const, error: "Tu sesión expiró" };
  const resultado = await consultarMonedapi(true);
  if (resultado === "falla") {
    revalidatePath("/", "layout");
    return {
      success: false as const,
      error: "No se pudo actualizar: se sigue usando el último guardado. Administración ya está avisada.",
    };
  }
  return { ...listo(), reciente: resultado === "reciente" };
}
