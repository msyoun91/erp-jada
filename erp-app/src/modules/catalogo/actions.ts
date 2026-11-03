"use server";

import { revalidatePath } from "next/cache";
import { argsRpc } from "@/lib/supabase/rpc";
import { createClient } from "@/lib/supabase/server";
import { mensajeError } from "@/lib/utils";
import { idSchema } from "@/lib/validacion";
import {
  activarSchema,
  avisoBajaSchema,
  categoriaAltaSchema,
  costosSchema,
  fijoEditarSchema,
  fijoSchema,
  insumoEditarSchema,
  insumoSchema,
  nombreAltaSchema,
  porcentajeSchema,
  renombrarSchema,
  revertirSchema,
  varianteSchema,
  type ActivarForm,
  type AvisoBaja,
  type AvisoBajaForm,
  type CategoriaAltaForm,
  type CostosForm,
  type FijoEditarForm,
  type FijoForm,
  type InsumoEditarForm,
  type InsumoForm,
  type NivelCosto,
  type PorcentajeForm,
  type RenombrarForm,
  type RevertirForm,
  type VarianteForm,
} from "./types";

// Quién puede qué lo deciden la RLS y las funciones de `sql/159`–`165`: acá solo se valida la forma,
// se llama y se traduce el error. Lo de una pestaña se ve en las otras (nombres de insumos en el
// despiece, categorías en los %): se revalida el módulo entero.

function fallo(error: unknown) {
  return { success: false as const, error: mensajeError(error) };
}

function invalido(issues: { message: string }[]) {
  return { success: false as const, error: issues[0].message };
}

function listo() {
  revalidatePath("/catalogo", "layout");
  return { success: true as const };
}

// ---------- Categorías y colores ----------

export async function crearCategoria(input: CategoriaAltaForm) {
  const parsed = categoriaAltaSchema.safeParse(input);
  if (!parsed.success) return invalido(parsed.error.issues);
  const supabase = await createClient();
  const { error } = await supabase.from("catalogo_categorias").insert(parsed.data);
  return error ? fallo(error) : listo();
}

export async function renombrarCategoria(input: RenombrarForm) {
  const parsed = renombrarSchema.safeParse(input);
  if (!parsed.success) return invalido(parsed.error.issues);
  const supabase = await createClient();
  const { error } = await supabase
    .from("catalogo_categorias")
    .update({ nombre: parsed.data.nombre })
    .eq("id", parsed.data.id);
  return error ? fallo(error) : listo();
}

export async function activarCategoria(input: ActivarForm) {
  const parsed = activarSchema.safeParse(input);
  if (!parsed.success) return invalido(parsed.error.issues);
  const supabase = await createClient();
  const { error } = await supabase
    .from("catalogo_categorias")
    .update({ activo: parsed.data.activo })
    .eq("id", parsed.data.id);
  return error ? fallo(error) : listo();
}

export async function crearColor(input: { nombre: string }) {
  const parsed = nombreAltaSchema.safeParse(input);
  if (!parsed.success) return invalido(parsed.error.issues);
  const supabase = await createClient();
  const { error } = await supabase.from("catalogo_colores").insert(parsed.data);
  return error ? fallo(error) : listo();
}

export async function renombrarColor(input: RenombrarForm) {
  const parsed = renombrarSchema.safeParse(input);
  if (!parsed.success) return invalido(parsed.error.issues);
  const supabase = await createClient();
  const { error } = await supabase
    .from("catalogo_colores")
    .update({ nombre: parsed.data.nombre })
    .eq("id", parsed.data.id);
  return error ? fallo(error) : listo();
}

export async function activarColor(input: ActivarForm) {
  const parsed = activarSchema.safeParse(input);
  if (!parsed.success) return invalido(parsed.error.issues);
  const supabase = await createClient();
  const { error } = await supabase
    .from("catalogo_colores")
    .update({ activo: parsed.data.activo })
    .eq("id", parsed.data.id);
  return error ? fallo(error) : listo();
}

// ---------- Insumos y servicios fijos ----------

export async function crearInsumo(input: InsumoForm) {
  const parsed = insumoSchema.safeParse(input);
  if (!parsed.success) return invalido(parsed.error.issues);
  const d = parsed.data;
  const supabase = await createClient();
  const { error } = await supabase.rpc("catalogo_insumo_alta", {
    p_nombre: d.nombre,
    p_categoria: d.categoria_id,
    p_unidad: d.unidad,
    p_peso: d.peso,
    p_espesor: d.espesor,
    p_colores: d.colores,
  });
  return error ? fallo(error) : listo();
}

// Un dato fijo (usado por una versión enviada) lo frena la base con CA006, que ya dice qué hacer.
export async function editarInsumo(input: InsumoEditarForm) {
  const parsed = insumoEditarSchema.safeParse(input);
  if (!parsed.success) return invalido(parsed.error.issues);
  const { id, nombre, categoria_id, unidad, peso, espesor, con_color } = parsed.data;
  const supabase = await createClient();
  const { error } = await supabase
    .from("catalogo_insumos")
    .update({ nombre, categoria_id, unidad, peso, espesor, con_color })
    .eq("id", id);
  return error ? fallo(error) : listo();
}

export async function crearFijo(input: FijoForm) {
  const parsed = fijoSchema.safeParse(input);
  if (!parsed.success) return invalido(parsed.error.issues);
  const d = parsed.data;
  const supabase = await createClient();
  const { error } = await supabase.rpc("catalogo_fijo_alta", {
    p_nombre: d.nombre,
    p_categoria: d.categoria_id,
    p_unidad: d.unidad,
    p_costo: d.costo,
    p_moneda: d.moneda,
  });
  return error ? fallo(error) : listo();
}

export async function editarFijo(input: FijoEditarForm) {
  const parsed = fijoEditarSchema.safeParse(input);
  if (!parsed.success) return invalido(parsed.error.issues);
  const { id, ...datos } = parsed.data;
  const supabase = await createClient();
  const { error } = await supabase.from("catalogo_insumos").update(datos).eq("id", id);
  return error ? fallo(error) : listo();
}

// La baja dispara la cascada (`catalogo_baja_cascada`): lo que sale de la venta lo decide la base.
export async function activarInsumo(input: ActivarForm) {
  const parsed = activarSchema.safeParse(input);
  if (!parsed.success) return invalido(parsed.error.issues);
  const supabase = await createClient();
  const { error } = await supabase
    .from("catalogo_insumos")
    .update({ activo: parsed.data.activo })
    .eq("id", parsed.data.id);
  return error ? fallo(error) : listo();
}

export async function avisoBaja(input: AvisoBajaForm) {
  const parsed = avisoBajaSchema.safeParse(input);
  if (!parsed.success) return invalido(parsed.error.issues);
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("catalogo_baja_aviso", {
    p_insumo: parsed.data.insumo_id,
    ...(parsed.data.variante_id ? { p_variante: parsed.data.variante_id } : {}),
  });
  if (error) return fallo(error);
  return { success: true as const, aviso: data as AvisoBaja };
}

// Sumar un color que estuvo reactiva su fila, con sus costos.
export async function sumarColor(input: VarianteForm) {
  const parsed = varianteSchema.safeParse(input);
  if (!parsed.success) return invalido(parsed.error.issues);
  const supabase = await createClient();
  const { error } = await supabase.rpc("catalogo_variante_sumar", {
    p_insumo: parsed.data.insumo_id,
    p_color: parsed.data.color_id,
  });
  return error ? fallo(error) : listo();
}

export async function quitarColor(varianteId: unknown) {
  const parsed = idSchema.safeParse(varianteId);
  if (!parsed.success) return invalido(parsed.error.issues);
  const supabase = await createClient();
  const { error } = await supabase.from("catalogo_variantes").update({ activo: false }).eq("id", parsed.data);
  return error ? fallo(error) : listo();
}

// ---------- Costos ----------

export async function revisarCostos(input: CostosForm) {
  const parsed = costosSchema.safeParse(input);
  if (!parsed.success) return invalido(parsed.error.issues);
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("catalogo_costos_niveles", { p_filas: parsed.data.filas });
  if (error) return fallo(error);
  return { success: true as const, niveles: data as NivelCosto[] };
}

// CA003: alguna fila cambia 50 % o más. La UI lo confirma de una vez y reintenta con `confirmar_rojo`.
export async function cargarCostos(input: CostosForm) {
  const parsed = costosSchema.safeParse(input);
  if (!parsed.success) return invalido(parsed.error.issues);
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("catalogo_costos_cargar", {
    p_filas: parsed.data.filas,
    p_confirmar_rojo: parsed.data.confirmar_rojo,
  });
  if (error?.code === "CA003") return { ...fallo(error), pideConfirmar: true as const };
  if (error) return fallo(error);
  revalidatePath("/catalogo", "layout");
  return { success: true as const, cargadas: data };
}

// ---------- Servicios en % ----------
// CA003 (el % cambia 50 % o más) se confirma y se reintenta, como los costos. CA004 (el paso 3 llega a
// 100), CA005 (no es el último cambio) y CA010 (nombre repetido) llegan con su mensaje.

export async function guardarPorcentaje(input: PorcentajeForm) {
  const parsed = porcentajeSchema.safeParse(input);
  if (!parsed.success) return invalido(parsed.error.issues);
  const d = parsed.data;
  const supabase = await createClient();
  const { data, error } = await supabase.rpc(
    "catalogo_porcentaje_guardar",
    argsRpc<"catalogo_porcentaje_guardar">({
      p_id: d.id,
      p_nombre: d.nombre,
      p_porcentaje: d.porcentaje,
      p_paso: d.paso,
      p_categorias: d.categorias,
      p_minimo: d.minimo,
      p_minimo_moneda: d.minimo === null ? null : d.minimo_moneda,
      p_minimo_por: d.minimo === null ? null : d.minimo_por,
      p_opcional: d.opcional,
      p_confirmar_rojo: d.confirmar_rojo,
    }),
  );
  if (error?.code === "CA003") return { ...fallo(error), pideConfirmar: true as const };
  if (error) return fallo(error);
  revalidatePath("/catalogo", "layout");
  return { success: true as const, id: data };
}

export async function activarPorcentaje(input: ActivarForm) {
  const parsed = activarSchema.safeParse(input);
  if (!parsed.success) return invalido(parsed.error.issues);
  const supabase = await createClient();
  const { error } = await supabase.rpc("catalogo_porcentaje_activar", {
    p_id: parsed.data.id,
    p_activo: parsed.data.activo,
  });
  return error ? fallo(error) : listo();
}

export async function revertirPorcentaje(input: RevertirForm) {
  const parsed = revertirSchema.safeParse(input);
  if (!parsed.success) return invalido(parsed.error.issues);
  const supabase = await createClient();
  const { error } = await supabase.rpc("catalogo_porcentaje_revertir", {
    p_valor_id: parsed.data.valor_id,
    p_confirmar_rojo: parsed.data.confirmar_rojo,
  });
  if (error?.code === "CA003") return { ...fallo(error), pideConfirmar: true as const };
  return error ? fallo(error) : listo();
}
