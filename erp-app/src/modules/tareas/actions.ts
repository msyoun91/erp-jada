"use server";

import { revalidatePath } from "next/cache";
import type { Database } from "@/lib/supabase/database.types";
import { argsRpc } from "@/lib/supabase/rpc";
import { createClient } from "@/lib/supabase/server";
import { mensajeError } from "@/lib/utils";
import {
  cerrarHiloSchema,
  completarAjenoSchema,
  completarSchema,
  editarPasoSchema,
  esperaSchema,
  hiloSchema,
  idSchema,
  insertarAntesSchema,
  notaSchema,
  pasoSchema,
  plantillaSchema,
  reasignarSchema,
  rechazarSchema,
  transferirSchema,
  usarPlantillaSchema,
  type CerrarHiloForm,
  type CompletarAjenoForm,
  type CompletarForm,
  type EditarPasoForm,
  type EsperaForm,
  type HiloForm,
  type InsertarAntesForm,
  type NotaForm,
  type PasoForm,
  type PlantillaForm,
  type ReasignarForm,
  type RechazarForm,
  type TransferirForm,
  type UsarPlantillaForm,
} from "./types";

// Quién puede qué lo deciden las policies y los triggers de `sql/113`: acá
// solo se valida la forma, se escribe y se traduce el error.

type Tablas = Database["public"]["Tables"];

function fallo(error: unknown) {
  return { success: false as const, error: mensajeError(error) };
}

function invalido(issues: { message: string }[]) {
  return { success: false as const, error: issues[0].message };
}

function listo() {
  revalidatePath("/tareas", "layout");
  return { success: true as const };
}

async function editarHiloFila(id: unknown, cambios: Tablas["tareas_hilos"]["Update"]) {
  const parsed = idSchema.safeParse(id);
  if (!parsed.success) return invalido(parsed.error.issues);
  const supabase = await createClient();
  const { error } = await supabase.from("tareas_hilos").update(cambios).eq("id", parsed.data);
  return error ? fallo(error) : listo();
}

async function editarPasoFila(id: unknown, cambios: Tablas["tareas"]["Update"]) {
  const parsed = idSchema.safeParse(id);
  if (!parsed.success) return invalido(parsed.error.issues);
  const supabase = await createClient();
  const { error } = await supabase.from("tareas").update(cambios).eq("id", parsed.data);
  return error ? fallo(error) : listo();
}

// ---------- Hilos ----------

// El id se genera acá: el hilo recién creado puede no pasar la policy de
// SELECT (un admin que lo crea para otro), y `.select()` fallaría.
export async function crearHilo(input: HiloForm) {
  const parsed = hiloSchema.safeParse(input);
  if (!parsed.success) return invalido(parsed.error.issues);
  const { titulo, recurrencia_cantidad, recurrencia_unidad } = parsed.data;
  const id = crypto.randomUUID();
  const supabase = await createClient();
  const { error } = await supabase
    .from("tareas_hilos")
    .insert({ id, titulo, recurrencia_cantidad, recurrencia_unidad });
  if (error) return fallo(error);
  revalidatePath("/tareas", "layout");
  return { success: true as const, id };
}

export async function editarHilo(input: HiloForm) {
  const parsed = hiloSchema.safeParse(input);
  if (!parsed.success) return invalido(parsed.error.issues);
  const { id, ...cambios } = parsed.data;
  return editarHiloFila(id, cambios);
}

export async function transferirHilo(input: TransferirForm) {
  const parsed = transferirSchema.safeParse(input);
  if (!parsed.success) return invalido(parsed.error.issues);
  const supabase = await createClient();
  const { error } = await supabase.rpc("tareas_transferir_hilo", {
    p_hilo: parsed.data.id,
    p_responsable: parsed.data.responsable_id,
  });
  return error ? fallo(error) : listo();
}

export async function cerrarHilo(input: CerrarHiloForm) {
  const parsed = cerrarHiloSchema.safeParse(input);
  if (!parsed.success) return invalido(parsed.error.issues);
  const { id, resultado, generar, cancelar_pendientes } = parsed.data;

  if (cancelar_pendientes) {
    const supabase = await createClient();
    const { error } = await supabase.rpc(
      "tareas_cancelar_y_cerrar",
      argsRpc<"tareas_cancelar_y_cerrar">({ p_hilo: id, p_resultado: resultado, p_generar: generar })
    );
    return error ? fallo(error) : listo();
  }

  // No generar el siguiente = cerrar sin recurrencia, en el mismo UPDATE.
  const sinRecurrencia = generar ? {} : { recurrencia_cantidad: null, recurrencia_unidad: null };
  return editarHiloFila(id, { estado: "cerrado", resultado, ...sinRecurrencia });
}

export async function reabrirHilo(id: string) {
  return editarHiloFila(id, { estado: "abierto" });
}

export async function desactivarHilo(id: string) {
  const parsed = idSchema.safeParse(id);
  if (!parsed.success) return invalido(parsed.error.issues);
  const supabase = await createClient();
  const { error } = await supabase.rpc("tareas_desactivar_hilo", { p_hilo: parsed.data });
  return error ? fallo(error) : listo();
}

export async function reactivarHilo(id: string) {
  return editarHiloFila(id, { activo: true });
}

// ---------- Pasos ----------

export async function crearPaso(input: PasoForm) {
  const parsed = pasoSchema.safeParse(input);
  if (!parsed.success) return invalido(parsed.error.issues);
  const id = crypto.randomUUID();
  const supabase = await createClient();
  const { error } = await supabase.from("tareas").insert({ id, ...parsed.data });
  if (error) return fallo(error);
  revalidatePath("/tareas", "layout");
  return { success: true as const, id };
}

export async function insertarPasoAntes(input: InsertarAntesForm) {
  const parsed = insertarAntesSchema.safeParse(input);
  if (!parsed.success) return invalido(parsed.error.issues);
  const p = parsed.data;
  const supabase = await createClient();
  const { data, error } = await supabase.rpc(
    "tareas_insertar_antes",
    argsRpc<"tareas_insertar_antes">({
      p_siguiente: p.siguiente_id,
      p_titulo: p.titulo,
      p_descripcion: p.descripcion,
      p_asignado_id: p.asignado_id,
      p_asignado_equipo_id: p.asignado_equipo_id,
      p_prioridad: p.prioridad,
      p_vence: p.vence,
      p_vence_dias: p.vence_dias,
    })
  );
  if (error) return fallo(error);
  revalidatePath("/tareas", "layout");
  return { success: true as const, id: data };
}

export async function editarPaso(input: EditarPasoForm) {
  const parsed = editarPasoSchema.safeParse(input);
  if (!parsed.success) return invalido(parsed.error.issues);
  const { id, ...cambios } = parsed.data;
  return editarPasoFila(id, cambios);
}

// El estado que queda (pendiente o solicitada) lo decide la base.
export async function reasignarPaso(input: ReasignarForm) {
  const parsed = reasignarSchema.safeParse(input);
  if (!parsed.success) return invalido(parsed.error.issues);
  const { id, ...asignado } = parsed.data;
  return editarPasoFila(id, asignado);
}

export async function aceptarPaso(id: string) {
  return editarPasoFila(id, { estado: "pendiente" });
}

export async function rechazarPaso(input: RechazarForm) {
  const parsed = rechazarSchema.safeParse(input);
  if (!parsed.success) return invalido(parsed.error.issues);
  return editarPasoFila(parsed.data.id, { estado: "rechazada", motivo_rechazo: parsed.data.motivo_rechazo });
}

export async function completarPaso(input: CompletarForm) {
  const parsed = completarSchema.safeParse(input);
  if (!parsed.success) return invalido(parsed.error.issues);
  return editarPasoFila(parsed.data.id, { estado: "completada", resultado: parsed.data.resultado });
}

export async function completarPasoAjeno(input: CompletarAjenoForm) {
  const parsed = completarAjenoSchema.safeParse(input);
  if (!parsed.success) return invalido(parsed.error.issues);
  const supabase = await createClient();
  const { error } = await supabase.rpc(
    "tareas_completar_con_nota",
    argsRpc<"tareas_completar_con_nota">({
      p_tarea: parsed.data.id,
      p_nota: parsed.data.nota,
      p_resultado: parsed.data.resultado,
    })
  );
  return error ? fallo(error) : listo();
}

export async function ponerEnEspera(input: EsperaForm) {
  const parsed = esperaSchema.safeParse(input);
  if (!parsed.success) return invalido(parsed.error.issues);
  const { id, ...espera } = parsed.data;
  return editarPasoFila(id, espera);
}

// Reabrir y volver a pedir mandan un estado abierto: el que queda (pendiente
// o solicitada) sale de `tareas_estado_al_abrir`.
export async function reabrirPaso(id: string) {
  return editarPasoFila(id, { estado: "pendiente" });
}

export async function volverAPedir(id: string) {
  return editarPasoFila(id, { estado: "solicitada" });
}

export async function cancelarPaso(id: string) {
  return editarPasoFila(id, { estado: "cancelada" });
}

export async function desactivarPaso(id: string) {
  const parsed = idSchema.safeParse(id);
  if (!parsed.success) return invalido(parsed.error.issues);
  const supabase = await createClient();
  const { error } = await supabase.rpc("tareas_desactivar_paso", { p_paso: parsed.data });
  return error ? fallo(error) : listo();
}

export async function reactivarPaso(id: string) {
  return editarPasoFila(id, { activo: true });
}

// ---------- Notas e historial ----------

export async function agregarNota(input: NotaForm) {
  const parsed = notaSchema.safeParse(input);
  if (!parsed.success) return invalido(parsed.error.issues);
  const supabase = await createClient();
  const { error } = await supabase.from("tareas_notas").insert(parsed.data);
  return error ? fallo(error) : listo();
}

export async function ocultarNota(id: string) {
  const parsed = idSchema.safeParse(id);
  if (!parsed.success) return invalido(parsed.error.issues);
  const supabase = await createClient();
  const { error } = await supabase.from("tareas_notas").update({ activo: false }).eq("id", parsed.data);
  return error ? fallo(error) : listo();
}

export async function ocultarEdicion(id: string) {
  const parsed = idSchema.safeParse(id);
  if (!parsed.success) return invalido(parsed.error.issues);
  const supabase = await createClient();
  const { error } = await supabase.from("tareas_ediciones").update({ activo: false }).eq("id", parsed.data);
  return error ? fallo(error) : listo();
}

// ---------- Plantillas ----------

export async function guardarPlantilla(input: PlantillaForm) {
  const parsed = plantillaSchema.safeParse(input);
  if (!parsed.success) return invalido(parsed.error.issues);
  const { id, nombre, descripcion, pasos } = parsed.data;
  const supabase = await createClient();
  const { data, error } = await supabase.rpc(
    "guardar_plantilla",
    argsRpc<"guardar_plantilla">({ p_id: id ?? null, p_nombre: nombre, p_descripcion: descripcion, p_pasos: pasos })
  );
  if (error) return fallo(error);
  revalidatePath("/tareas", "layout");
  return { success: true as const, id: data };
}

export async function copiarPlantilla(id: string) {
  const parsed = idSchema.safeParse(id);
  if (!parsed.success) return invalido(parsed.error.issues);
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("copiar_plantilla", { p_plantilla: parsed.data });
  if (error) return fallo(error);
  revalidatePath("/tareas", "layout");
  return { success: true as const, id: data };
}

export async function usarPlantilla(input: UsarPlantillaForm) {
  const parsed = usarPlantillaSchema.safeParse(input);
  if (!parsed.success) return invalido(parsed.error.issues);
  const { plantilla_id, titulo, hilo_id, asignados } = parsed.data;
  const supabase = await createClient();
  const { data, error } = await supabase.rpc(
    "usar_plantilla",
    argsRpc<"usar_plantilla">({ p_plantilla: plantilla_id, p_titulo: titulo, p_hilo: hilo_id, p_asignados: asignados })
  );
  if (error) return fallo(error);
  revalidatePath("/tareas", "layout");
  return { success: true as const, id: data };
}

async function editarPlantillaFila(id: unknown, cambios: Tablas["tareas_plantillas"]["Update"]) {
  const parsed = idSchema.safeParse(id);
  if (!parsed.success) return invalido(parsed.error.issues);
  const supabase = await createClient();
  const { error } = await supabase.from("tareas_plantillas").update(cambios).eq("id", parsed.data);
  return error ? fallo(error) : listo();
}

export async function publicarPlantilla(id: string, publicada: boolean) {
  return editarPlantillaFila(id, { publicada });
}

export async function desactivarPlantilla(id: string) {
  return editarPlantillaFila(id, { activo: false });
}

export async function reactivarPlantilla(id: string) {
  return editarPlantillaFila(id, { activo: true });
}
