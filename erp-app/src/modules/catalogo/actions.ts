"use server";

import { revalidatePath } from "next/cache";
import { argsRpc } from "@/lib/supabase/rpc";
import { createClient } from "@/lib/supabase/server";
import { mensajeError } from "@/lib/utils";
import { idSchema } from "@/lib/validacion";
import {
  activarSchema,
  avisoBajaSchema,
  calcularSchema,
  categoriaAltaSchema,
  costosSchema,
  devolverSchema,
  duplicarSchema,
  fijoEditarSchema,
  fijoSchema,
  insumoEditarSchema,
  insumoSchema,
  nombreAltaSchema,
  paqueteAltaSchema,
  porcentajeSchema,
  renombrarSchema,
  revertirSchema,
  varianteSchema,
  versionNuevaSchema,
  type ActivarForm,
  type AvisoBaja,
  type AvisoBajaForm,
  type CalcularForm,
  type CategoriaAltaForm,
  type CostosForm,
  type Despiece,
  type DevolverForm,
  type DuplicarForm,
  type FijoEditarForm,
  type FijoForm,
  type InsumoEditarForm,
  type InsumoForm,
  type NivelCosto,
  type PaqueteAltaForm,
  type PorcentajeForm,
  type PrecioDetalle,
  type RenombrarForm,
  type RevertirForm,
  type VarianteForm,
  type VersionNuevaForm,
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

// ---------- Paquetes y el ciclo de una versión ----------
// Las funciones del ciclo toman la versión con su permiso y estado (`catalogo_version_tomar`): CA012 fuera
// de borrador, CA019 con la lista de lo que frena, CA022 fuera de revisión, CA023 descartar sin publicada.

export async function crearPaquete(input: PaqueteAltaForm) {
  const parsed = paqueteAltaSchema.safeParse(input);
  if (!parsed.success) return invalido(parsed.error.issues);
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("catalogo_paquete_alta", {
    p_nombre: parsed.data.nombre,
    p_categoria: parsed.data.categoria_id,
  });
  if (error) return fallo(error);
  revalidatePath("/catalogo", "layout");
  return { success: true as const, version_id: data };
}

export async function duplicarPaquete(input: DuplicarForm) {
  const parsed = duplicarSchema.safeParse(input);
  if (!parsed.success) return invalido(parsed.error.issues);
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("catalogo_paquete_duplicar", {
    p_version: parsed.data.version_id,
    p_nombre: parsed.data.nombre,
  });
  if (error) return fallo(error);
  revalidatePath("/catalogo", "layout");
  return { success: true as const, version_id: data };
}

export async function versionNueva(input: VersionNuevaForm) {
  const parsed = versionNuevaSchema.safeParse(input);
  if (!parsed.success) return invalido(parsed.error.issues);
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("catalogo_version_nueva", {
    p_paquete: parsed.data.paquete_id,
    p_origen: parsed.data.origen_id,
  });
  if (error) return fallo(error);
  revalidatePath("/catalogo", "layout");
  return { success: true as const, version_id: data };
}

// CA008 (categoría de baja) y CA020 (no se arma en ningún color, con lo que falta) llegan con su mensaje.
export async function activarPaquete(input: ActivarForm) {
  const parsed = activarSchema.safeParse(input);
  if (!parsed.success) return invalido(parsed.error.issues);
  const supabase = await createClient();
  const { error } = await supabase
    .from("catalogo_paquetes")
    .update({ activo: parsed.data.activo })
    .eq("id", parsed.data.id);
  return error ? fallo(error) : listo();
}

const CICLO = {
  enviar: "catalogo_version_enviar",
  retirar: "catalogo_version_retirar",
  aprobar: "catalogo_version_aprobar",
  descartar: "catalogo_version_descartar",
} as const;

export async function moverVersion(accion: keyof typeof CICLO, versionId: unknown) {
  const parsed = idSchema.safeParse(versionId);
  if (!parsed.success || !(accion in CICLO)) return invalido([{ message: "Pedido inválido" }]);
  const supabase = await createClient();
  const { error } = await supabase.rpc(CICLO[accion], { p_version: parsed.data });
  return error ? fallo(error) : listo();
}

export async function devolverVersion(input: DevolverForm) {
  const parsed = devolverSchema.safeParse(input);
  if (!parsed.success) return invalido(parsed.error.issues);
  const supabase = await createClient();
  const { error } = await supabase.rpc("catalogo_version_devolver", {
    p_version: parsed.data.version_id,
    p_motivo: parsed.data.motivo,
  });
  return error ? fallo(error) : listo();
}

// El despiece, o con `catalogo_aprobar` el precio con su detalle, que lo incluye. La comparación es la
// publicada con la misma entrada y la misma fecha: la diferencia sale solo de la versión.
export async function calcular(input: CalcularForm) {
  const parsed = calcularSchema.safeParse(input);
  if (!parsed.success) return invalido(parsed.error.issues);
  const { version_id, entrada, precio } = parsed.data;
  const supabase = await createClient();
  if (!precio) {
    const { data, error } = await supabase.rpc("catalogo_despiece", { p_version: version_id, p_entrada: entrada });
    if (error) return fallo(error);
    return { success: true as const, resultado: data as unknown as Despiece, comparado: null };
  }
  const en = new Date().toISOString();
  const detalle = (id: string) =>
    supabase.rpc("catalogo_precio_detalle", {
      p_version: id,
      p_entrada: entrada,
      p_opcionales: precio.opcionales,
      p_moneda: precio.moneda,
      p_en: en,
    });
  const [esta, otra] = await Promise.all([
    detalle(version_id),
    precio.comparar_con ? detalle(precio.comparar_con) : Promise.resolve(null),
  ]);
  if (esta.error) return fallo(esta.error);
  if (otra?.error) return fallo(otra.error);
  return {
    success: true as const,
    resultado: esta.data as unknown as PrecioDetalle,
    comparado: (otra?.data ?? null) as unknown as PrecioDetalle | null,
  };
}
