"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { puedeAsignarTarea, puedeCrearTarea, puedeVerPlantillas } from "./permissions";
import {
  getHistorialHilo,
  getMisTareasCompletadas,
  getNotasDeTarea,
  getPlantillas,
  getTodasLasTareasCompletadas,
} from "./queries";
import {
  actualizarEstadoSchema,
  agregarDesdePlantillaSchema,
  agregarNotaSchema,
  asociarHiloSchema,
  crearHiloSchema,
  crearPlantillaSchema,
  crearTareaSchema,
  type ActualizarEstadoForm,
  type AgregarDesdePlantillaForm,
  type AgregarNotaForm,
  type AsociarHiloForm,
  type CrearHiloForm,
  type CrearPlantillaForm,
  type CrearTareaForm,
} from "./types";

export async function crearHilo(input: CrearHiloForm) {
  if (!(await puedeCrearTarea())) {
    return { success: false as const, error: "No autorizado" };
  }

  const parsed = crearHiloSchema.safeParse(input);
  if (!parsed.success) {
    return { success: false as const, error: parsed.error.issues[0].message };
  }

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return { success: false as const, error: "No autorizado" };

  const { data, error } = await supabase
    .from("tareas_hilos")
    .insert({ ...parsed.data, creado_por: user.id })
    .select("id")
    .single();

  if (error) return { success: false as const, error: error.message };

  revalidatePath("/tareas");
  return { success: true as const, hilo_id: data.id };
}

export async function crearTarea(input: CrearTareaForm) {
  if (!(await puedeCrearTarea())) {
    return { success: false as const, error: "No autorizado" };
  }

  const parsed = crearTareaSchema.safeParse(input);
  if (!parsed.success) {
    return { success: false as const, error: parsed.error.issues[0].message };
  }

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return { success: false as const, error: "No autorizado" };

  if (parsed.data.asignado_a !== user.id && !(await puedeAsignarTarea())) {
    return { success: false as const, error: "No autorizado para asignar a otro usuario" };
  }

  const { error } = await supabase.from("tareas").insert({
    ...parsed.data,
    fecha_vencimiento: parsed.data.fecha_vencimiento || null,
    creado_por: user.id,
  });

  if (error) return { success: false as const, error: error.message };

  revalidatePath("/tareas");
  return { success: true as const };
}

export async function actualizarEstadoTarea(input: ActualizarEstadoForm) {
  const parsed = actualizarEstadoSchema.safeParse(input);
  if (!parsed.success) {
    return { success: false as const, error: parsed.error.issues[0].message };
  }

  const supabase = await createClient();
  const { error } = await supabase
    .from("tareas")
    .update({ estado: parsed.data.estado })
    .eq("id", parsed.data.tarea_id);

  if (error) return { success: false as const, error: error.message };

  revalidatePath("/tareas");
  return { success: true as const };
}

export async function agregarNota(input: AgregarNotaForm) {
  const parsed = agregarNotaSchema.safeParse(input);
  if (!parsed.success) {
    return { success: false as const, error: parsed.error.issues[0].message };
  }

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return { success: false as const, error: "No autorizado" };

  const { error } = await supabase
    .from("tareas_notas")
    .insert({ tarea_id: parsed.data.tarea_id, usuario_id: user.id, nota: parsed.data.nota });

  if (error) return { success: false as const, error: error.message };

  revalidatePath("/tareas");
  return { success: true as const };
}

export async function obtenerHistorialHilo(hiloId: string) {
  return getHistorialHilo(hiloId);
}

export async function obtenerNotasTarea(tareaId: string) {
  return getNotasDeTarea(tareaId);
}

export async function desactivarTarea(tareaId: string) {
  const supabase = await createClient();
  const { error } = await supabase.from("tareas").update({ activo: false }).eq("id", tareaId);

  if (error) return { success: false as const, error: error.message };

  revalidatePath("/tareas");
  return { success: true as const };
}

export async function asociarTareaHilo(input: AsociarHiloForm) {
  const parsed = asociarHiloSchema.safeParse(input);
  if (!parsed.success) {
    return { success: false as const, error: parsed.error.issues[0].message };
  }

  const supabase = await createClient();
  const { error } = await supabase
    .from("tareas")
    .update({ hilo_id: parsed.data.hilo_id })
    .eq("id", parsed.data.tarea_id);

  if (error) return { success: false as const, error: error.message };

  revalidatePath("/tareas");
  return { success: true as const };
}

export async function desasociarTareaHilo(tareaId: string) {
  const supabase = await createClient();
  const { error } = await supabase.from("tareas").update({ hilo_id: null }).eq("id", tareaId);

  if (error) return { success: false as const, error: error.message };

  revalidatePath("/tareas");
  return { success: true as const };
}

export async function obtenerTareasCompletadas(modo: "mis" | "todas") {
  return modo === "mis" ? getMisTareasCompletadas() : getTodasLasTareasCompletadas();
}

export async function desactivarHilo(hiloId: string) {
  const supabase = await createClient();

  const { count, error: countError } = await supabase
    .from("tareas")
    .select("id", { count: "exact", head: true })
    .eq("hilo_id", hiloId)
    .eq("activo", true);

  if (countError) return { success: false as const, error: countError.message };
  if ((count ?? 0) > 0) {
    return { success: false as const, error: "El hilo tiene tareas activas, movelas o eliminalas primero" };
  }

  const { error } = await supabase.from("tareas_hilos").update({ activo: false }).eq("id", hiloId);
  if (error) return { success: false as const, error: error.message };

  revalidatePath("/tareas");
  return { success: true as const };
}

export async function crearPlantilla(input: CrearPlantillaForm) {
  if (!(await puedeVerPlantillas())) {
    return { success: false as const, error: "No autorizado" };
  }

  const parsed = crearPlantillaSchema.safeParse(input);
  if (!parsed.success) {
    return { success: false as const, error: parsed.error.issues[0].message };
  }

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return { success: false as const, error: "No autorizado" };

  const { data: plantilla, error: plantillaError } = await supabase
    .from("tareas_plantillas")
    .insert({ nombre: parsed.data.nombre, creado_por: user.id })
    .select("id")
    .single();

  if (plantillaError) return { success: false as const, error: plantillaError.message };

  const { error: itemsError } = await supabase.from("tareas_plantillas_items").insert(
    parsed.data.items.map((item, index) => ({
      plantilla_id: plantilla.id,
      titulo: item.titulo,
      descripcion: item.descripcion || null,
      orden: index,
    }))
  );

  if (itemsError) return { success: false as const, error: itemsError.message };

  revalidatePath("/tareas/plantillas");
  return { success: true as const };
}

export async function actualizarPlantilla(plantillaId: string, input: CrearPlantillaForm) {
  if (!(await puedeVerPlantillas())) {
    return { success: false as const, error: "No autorizado" };
  }

  const parsed = crearPlantillaSchema.safeParse(input);
  if (!parsed.success) {
    return { success: false as const, error: parsed.error.issues[0].message };
  }

  const supabase = await createClient();

  const { error: nombreError } = await supabase
    .from("tareas_plantillas")
    .update({ nombre: parsed.data.nombre })
    .eq("id", plantillaId);

  if (nombreError) return { success: false as const, error: nombreError.message };

  const { error: deactivateError } = await supabase
    .from("tareas_plantillas_items")
    .update({ activo: false })
    .eq("plantilla_id", plantillaId);

  if (deactivateError) return { success: false as const, error: deactivateError.message };

  const { error: itemsError } = await supabase.from("tareas_plantillas_items").insert(
    parsed.data.items.map((item, index) => ({
      plantilla_id: plantillaId,
      titulo: item.titulo,
      descripcion: item.descripcion || null,
      orden: index,
    }))
  );

  if (itemsError) return { success: false as const, error: itemsError.message };

  revalidatePath("/tareas/plantillas");
  return { success: true as const };
}

export async function desactivarPlantilla(plantillaId: string) {
  if (!(await puedeVerPlantillas())) {
    return { success: false as const, error: "No autorizado" };
  }

  const supabase = await createClient();
  const { error } = await supabase
    .from("tareas_plantillas")
    .update({ activo: false })
    .eq("id", plantillaId);

  if (error) return { success: false as const, error: error.message };

  revalidatePath("/tareas/plantillas");
  return { success: true as const };
}

export async function obtenerPlantillas() {
  return getPlantillas();
}

export async function agregarTareasDesdePlantilla(input: AgregarDesdePlantillaForm) {
  if (!(await puedeCrearTarea())) {
    return { success: false as const, error: "No autorizado" };
  }

  const parsed = agregarDesdePlantillaSchema.safeParse(input);
  if (!parsed.success) {
    return { success: false as const, error: parsed.error.issues[0].message };
  }

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return { success: false as const, error: "No autorizado" };

  if (parsed.data.asignado_a !== user.id && !(await puedeAsignarTarea())) {
    return { success: false as const, error: "No autorizado para asignar a otro usuario" };
  }

  const { data: items, error: itemsError } = await supabase
    .from("tareas_plantillas_items")
    .select("titulo, descripcion")
    .eq("plantilla_id", parsed.data.plantilla_id)
    .eq("activo", true)
    .order("orden");

  if (itemsError) return { success: false as const, error: itemsError.message };
  if (items.length === 0) return { success: false as const, error: "La plantilla no tiene tareas" };

  const { error } = await supabase.from("tareas").insert(
    items.map((item) => ({
      hilo_id: parsed.data.hilo_id,
      titulo: item.titulo,
      descripcion: item.descripcion,
      asignado_a: parsed.data.asignado_a,
      creado_por: user.id,
    }))
  );

  if (error) return { success: false as const, error: error.message };

  revalidatePath("/tareas");
  return { success: true as const };
}
