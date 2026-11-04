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
  casoSchema,
  colorVersionSchema,
  condicionSchema,
  categoriaAltaSchema,
  costosSchema,
  devolverSchema,
  duplicarSchema,
  fijoEditarSchema,
  fijoSchema,
  insumoEditarSchema,
  insumoSchema,
  materialSchema,
  nombreAltaSchema,
  opcionSchema,
  ordenarSchema,
  paqueteAltaSchema,
  piezaSchema,
  porcentajeSchema,
  renombrarSchema,
  revertirSchema,
  sacarSchema,
  valorVariableSchema,
  varianteSchema,
  variableSchema,
  versionDatosSchema,
  versionNuevaSchema,
  type ActivarForm,
  type AvisoBaja,
  type AvisoBajaForm,
  type CalcularForm,
  type CasoForm,
  type ColorVersionForm,
  type CondicionForm,
  type CategoriaAltaForm,
  type CostosForm,
  type Despiece,
  type DevolverForm,
  type DuplicarForm,
  type FijoEditarForm,
  type FijoForm,
  type InsumoEditarForm,
  type InsumoForm,
  type MaterialForm,
  type NivelCosto,
  type OpcionForm,
  type OrdenarForm,
  type PaqueteAltaForm,
  type PiezaForm,
  type PorcentajeForm,
  type PrecioDetalle,
  type RenombrarForm,
  type ValorVariableForm,
  type RevertirForm,
  type SacarForm,
  type TablaContenido,
  type VarianteForm,
  type VariableForm,
  type VersionDatosForm,
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

// Con RLS, un UPDATE sin permiso no da error: no encuentra filas. Como nada se borra, 0 filas es eso.
const SIN_PERMISO = { code: "42501" };

function actualizado({ data, error }: { data: unknown[] | null; error: unknown }) {
  if (error) return fallo(error);
  return data?.length ? listo() : fallo(SIN_PERMISO);
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
  const resultado = await supabase
    .from("catalogo_categorias")
    .update({ nombre: parsed.data.nombre })
    .eq("id", parsed.data.id)
    .select("id");
  return actualizado(resultado);
}

export async function activarCategoria(input: ActivarForm) {
  const parsed = activarSchema.safeParse(input);
  if (!parsed.success) return invalido(parsed.error.issues);
  const supabase = await createClient();
  const resultado = await supabase
    .from("catalogo_categorias")
    .update({ activo: parsed.data.activo })
    .eq("id", parsed.data.id)
    .select("id");
  return actualizado(resultado);
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
  const resultado = await supabase
    .from("catalogo_colores")
    .update({ nombre: parsed.data.nombre })
    .eq("id", parsed.data.id)
    .select("id");
  return actualizado(resultado);
}

export async function activarColor(input: ActivarForm) {
  const parsed = activarSchema.safeParse(input);
  if (!parsed.success) return invalido(parsed.error.issues);
  const supabase = await createClient();
  const resultado = await supabase
    .from("catalogo_colores")
    .update({ activo: parsed.data.activo })
    .eq("id", parsed.data.id)
    .select("id");
  return actualizado(resultado);
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
  const resultado = await supabase
    .from("catalogo_insumos")
    .update({ nombre, categoria_id, unidad, peso, espesor, con_color })
    .eq("id", id)
    .select("id");
  return actualizado(resultado);
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
  return actualizado(await supabase.from("catalogo_insumos").update(datos).eq("id", id).select("id"));
}

// La baja dispara la cascada (`catalogo_baja_cascada`): lo que sale de la venta lo decide la base.
export async function activarInsumo(input: ActivarForm) {
  const parsed = activarSchema.safeParse(input);
  if (!parsed.success) return invalido(parsed.error.issues);
  const supabase = await createClient();
  const resultado = await supabase
    .from("catalogo_insumos")
    .update({ activo: parsed.data.activo })
    .eq("id", parsed.data.id)
    .select("id");
  return actualizado(resultado);
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
  return actualizado(await supabase.from("catalogo_variantes").update({ activo: false }).eq("id", parsed.data).select("id"));
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
  const resultado = await supabase
    .from("catalogo_paquetes")
    .update({ activo: parsed.data.activo })
    .eq("id", parsed.data.id)
    .select("id");
  return actualizado(resultado);
}

const CICLO = {
  enviar: "catalogo_version_enviar",
  retirar: "catalogo_version_retirar",
  aprobar: "catalogo_version_aprobar",
  descartar: "catalogo_version_descartar",
} as const;

export async function moverVersion(accion: keyof typeof CICLO, versionId: unknown) {
  const parsed = idSchema.safeParse(versionId);
  if (!parsed.success || !Object.hasOwn(CICLO, accion)) return invalido([{ message: "Pedido inválido" }]);
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

// ---------- Editor del borrador ----------
// Casi todo se escribe directo: la RLS pide `catalogo_armar`, los triggers frenan fuera de borrador (CA012) y lo
// que no se entiende de una fórmula (CA001, con lo que falta). Lo único que se traduce acá es el nombre
// repetido, que la base da como 23505 sin decir de qué. Lo de varios pasos lo hace la base (`sql/173`).

const REPETIDO: Record<TablaContenido, string> = {
  catalogo_piezas: "Ya hay una pieza con ese nombre en la versión",
  catalogo_variables: "Ya hay una variable con ese nombre en la versión",
  catalogo_variables_valores: "Esa opción ya tiene un valor",
  catalogo_materiales: "Ya hay un material múltiple con ese nombre en la pieza",
  catalogo_opciones: "Ese insumo ya es una opción, o ya hay una predeterminada",
  catalogo_condiciones: "Esa condición ya está",
  catalogo_casos: "Ya hay un caso con ese nombre en la versión",
  catalogo_versiones_colores: "Ese color ya está en la versión, o ya hay uno base",
};

function falloContenido(tabla: TablaContenido, error: { code?: string }) {
  return error.code === "23505" ? { success: false as const, error: REPETIDO[tabla] } : fallo(error);
}

function listoContenido(tabla: TablaContenido, error: { code?: string } | null) {
  return error ? falloContenido(tabla, error) : listo();
}

function actualizadoContenido(
  tabla: TablaContenido,
  { data, error }: { data: unknown[] | null; error: { code?: string } | null },
) {
  return error ? falloContenido(tabla, error) : actualizado({ data, error });
}

export async function guardarVersionDatos(input: VersionDatosForm) {
  const parsed = versionDatosSchema.safeParse(input);
  if (!parsed.success) return invalido(parsed.error.issues);
  const supabase = await createClient();
  const resultado = await supabase
    .from("catalogo_versiones")
    .update({ nombre: parsed.data.nombre, categoria_id: parsed.data.categoria_id })
    .eq("id", parsed.data.id)
    .select("id");
  return actualizado(resultado);
}

export async function sumarColorVersion(input: ColorVersionForm) {
  const parsed = colorVersionSchema.safeParse(input);
  if (!parsed.success) return invalido(parsed.error.issues);
  const supabase = await createClient();
  const { error } = await supabase.rpc("catalogo_version_color_sumar", {
    p_version: parsed.data.version_id,
    p_color: parsed.data.color_id,
  });
  return listoContenido("catalogo_versiones_colores", error);
}

// El que estaba lo apaga la base (`catalogo_color_base_apagar`).
export async function marcarColorBase(colorVersionId: unknown) {
  const parsed = idSchema.safeParse(colorVersionId);
  if (!parsed.success) return invalido(parsed.error.issues);
  const supabase = await createClient();
  const resultado = await supabase
    .from("catalogo_versiones_colores")
    .update({ base: true })
    .eq("id", parsed.data)
    .select("id");
  return actualizadoContenido("catalogo_versiones_colores", resultado);
}

export async function guardarPieza(input: PiezaForm) {
  const parsed = piezaSchema.safeParse(input);
  if (!parsed.success) return invalido(parsed.error.issues);
  const { id, version_id, orden, ...datos } = parsed.data;
  const supabase = await createClient();
  const resultado = id
    ? await supabase.from("catalogo_piezas").update(datos).eq("id", id).select("id")
    : await supabase.from("catalogo_piezas").insert({ ...datos, version_id, orden }).select("id");
  return actualizadoContenido("catalogo_piezas", resultado);
}

export async function guardarVariable(input: VariableForm) {
  const parsed = variableSchema.safeParse(input);
  if (!parsed.success) return invalido(parsed.error.issues);
  const { id, version_id, orden, ...datos } = parsed.data;
  const supabase = await createClient();
  const { data, error } = id
    ? await supabase.from("catalogo_variables").update(datos).eq("id", id).select("id").maybeSingle()
    : await supabase
        .from("catalogo_variables")
        .insert({ ...datos, version_id, orden })
        .select("id")
        .single();
  if (error) return falloContenido("catalogo_variables", error);
  if (!data) return fallo(SIN_PERMISO);
  revalidatePath("/catalogo", "layout");
  return { success: true as const, id: data.id };
}

export async function guardarValorVariable(input: ValorVariableForm) {
  const parsed = valorVariableSchema.safeParse(input);
  if (!parsed.success) return invalido(parsed.error.issues);
  const { id, formula, ...resto } = parsed.data;
  const supabase = await createClient();
  const resultado = id
    ? await supabase.from("catalogo_variables_valores").update({ formula }).eq("id", id).select("id")
    : await supabase.from("catalogo_variables_valores").insert({ ...resto, formula }).select("id");
  return actualizadoContenido("catalogo_variables_valores", resultado);
}

export async function guardarMaterial(input: MaterialForm) {
  const parsed = materialSchema.safeParse(input);
  if (!parsed.success) return invalido(parsed.error.issues);
  const { id, version_id, orden, ...datos } = parsed.data;
  const supabase = await createClient();
  const { data, error } = id
    ? await supabase.from("catalogo_materiales").update(datos).eq("id", id).select("id").maybeSingle()
    : await supabase
        .from("catalogo_materiales")
        .insert({ ...datos, version_id, orden })
        .select("id")
        .single();
  if (error) return falloContenido("catalogo_materiales", error);
  if (!data) return fallo(SIN_PERMISO);
  revalidatePath("/catalogo", "layout");
  return { success: true as const, id: data.id };
}

// La predeterminada anterior la apaga la base (`catalogo_predeterminada_apagar`).
export async function guardarOpcion(input: OpcionForm) {
  const parsed = opcionSchema.safeParse(input);
  if (!parsed.success) return invalido(parsed.error.issues);
  const { id, version_id, orden, ...datos } = parsed.data;
  const supabase = await createClient();
  // `material_id` no se cambia: sin GRANT de UPDATE.
  const resultado = id
    ? await supabase
        .from("catalogo_opciones")
        .update({ ...datos, material_id: undefined })
        .eq("id", id)
        .select("id")
    : await supabase.from("catalogo_opciones").insert({ ...datos, version_id, orden }).select("id");
  return actualizadoContenido("catalogo_opciones", resultado);
}

export async function guardarCondicion(input: CondicionForm) {
  const parsed = condicionSchema.safeParse(input);
  if (!parsed.success) return invalido(parsed.error.issues);
  const { id, version_id, variable_id, material_id, opcion_id, ...datos } = parsed.data;
  const supabase = await createClient();
  const resultado = id
    ? await supabase.from("catalogo_condiciones").update(datos).eq("id", id).select("id")
    : await supabase
        .from("catalogo_condiciones")
        .insert({ ...datos, version_id, variable_id, material_id, opcion_id })
        .select("id");
  return actualizadoContenido("catalogo_condiciones", resultado);
}

export async function guardarCaso(input: CasoForm) {
  const parsed = casoSchema.safeParse(input);
  if (!parsed.success) return invalido(parsed.error.issues);
  const supabase = await createClient();
  const { error } = await supabase.from("catalogo_casos").insert(parsed.data);
  return listoContenido("catalogo_casos", error);
}

// Sacar algo de un borrador saca lo que depende de ello y no vuelve (`catalogo_contenido_baja`, CA015).
export async function sacar(input: SacarForm) {
  const parsed = sacarSchema.safeParse(input);
  if (!parsed.success) return invalido(parsed.error.issues);
  const supabase = await createClient();
  return actualizado(await supabase.from(parsed.data.tabla).update({ activo: false }).eq("id", parsed.data.id).select("id"));
}

export async function ordenar(input: OrdenarForm) {
  const parsed = ordenarSchema.safeParse(input);
  if (!parsed.success) return invalido(parsed.error.issues);
  const supabase = await createClient();
  const { error } = await supabase.rpc("catalogo_contenido_ordenar", {
    p_tabla: parsed.data.tabla,
    p_ids: parsed.data.ids,
  });
  return error ? fallo(error) : listo();
}
