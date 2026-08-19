"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { hoyISO, mensajeError } from "@/lib/utils";
import {
  crearTareaSchema,
  editarTareaSchema,
  crearHiloSchema,
  editarHiloSchema,
  crearProyectoSchema,
  editarProyectoSchema,
  crearPlantillaSchema,
  editarPlantillaSchema,
  reasignarTareaSchema,
  posponerSchema,
  completarTareaSchema,
  cerrarHiloSchema,
  agregarDesdePlantillaSchema,
  deshacerConversionSchema,
  agregarNotaTareaSchema,
  agregarNotaHiloSchema,
  type CrearTareaForm,
  type EditarTareaForm,
  type CrearHiloForm,
  type EditarHiloForm,
  type CrearProyectoForm,
  type EditarProyectoForm,
  type CrearPlantillaForm,
  type EditarPlantillaForm,
  type ReasignarTareaForm,
  type PosponerForm,
  type CompletarTareaForm,
  type CerrarHiloForm,
  type AgregarDesdePlantillaForm,
  type DeshacerConversionForm,
  type AgregarNotaTareaForm,
  type AgregarNotaHiloForm,
  type TareaNota,
  type HiloNota,
} from "./types";

// Sin chequeo de permisos acá: estas actions usan el cliente normal (no
// service_role), así que RLS ya autoriza cada operación a nivel fila —
// duplicar el chequeo en la action no agrega barrera, solo un segundo
// lugar donde desincronizarse (a diferencia de modules/usuarios/actions.ts,
// que usa cliente admin y sí necesita el chequeo porque bypasea RLS).
async function usuarioActualId() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) throw new Error("No autenticado");
  return user.id;
}

export async function crearTarea(input: CrearTareaForm) {
  const parsed = crearTareaSchema.safeParse(input);
  if (!parsed.success) {
    return { success: false as const, error: parsed.error.issues[0].message };
  }

  const supabase = await createClient();
  const creado_por = await usuarioActualId();
  const { asignados, ...tarea } = parsed.data;
  // id generado en el server: mismo motivo que crearHilo — tareas_select ya no
  // mira creado_por, así que la fila recién insertada todavía no es visible
  // (sus asignados se insertan después) y pedir RETURNING rompería con RLS.
  const id = crypto.randomUUID();

  const { error } = await supabase.from("tareas").insert({ id, ...tarea, creado_por });

  if (error) return { success: false as const, error: mensajeError(error) };

  const { error: errorAsignados } = await supabase
    .from("tareas_asignados")
    .insert(asignados.map((usuario_id) => ({ tarea_id: id, usuario_id })));

  if (errorAsignados) return { success: false as const, error: mensajeError(errorAsignados) };

  revalidatePath("/tareas");
  return { success: true as const, id };
}

export async function editarTarea(input: EditarTareaForm) {
  const parsed = editarTareaSchema.safeParse(input);
  if (!parsed.success) {
    return { success: false as const, error: parsed.error.issues[0].message };
  }

  const supabase = await createClient();
  const { id, ...campos } = parsed.data;

  const { error } = await supabase.from("tareas").update(campos).eq("id", id);
  if (error) return { success: false as const, error: mensajeError(error) };

  revalidatePath("/tareas");
  return { success: true as const };
}

export async function crearHilo(input: CrearHiloForm) {
  const parsed = crearHiloSchema.safeParse(input);
  if (!parsed.success) {
    return { success: false as const, error: parsed.error.issues[0].message };
  }

  const supabase = await createClient();
  const creado_por = await usuarioActualId();
  // id generado en el server: puede_ver_hilo() vuelve a consultar tareas_hilos
  // para la policy de SELECT, y esa consulta no ve la fila recién insertada
  // dentro del mismo statement — pedir RETURNING (.select()) rompe con RLS
  // violation aunque la fila sea 100% visible en un statement aparte.
  const id = crypto.randomUUID();

  const { error } = await supabase.from("tareas_hilos").insert({ id, ...parsed.data, creado_por });

  if (error) return { success: false as const, error: mensajeError(error) };

  revalidatePath("/tareas");
  return { success: true as const, id };
}

export async function editarHilo(input: EditarHiloForm) {
  const parsed = editarHiloSchema.safeParse(input);
  if (!parsed.success) {
    return { success: false as const, error: parsed.error.issues[0].message };
  }

  const supabase = await createClient();
  const { id, ...campos } = parsed.data;

  const { error } = await supabase.from("tareas_hilos").update(campos).eq("id", id);
  if (error) return { success: false as const, error: mensajeError(error) };

  revalidatePath("/tareas");
  revalidatePath("/tareas/proyectos");
  return { success: true as const };
}

// §1 spec: una tarea suelta se convierte en hilo. El título/descripción de
// la tarea pasan a ser los del hilo y la tarea original queda como su primer
// paso — no se crea un paso extra acá: la UI abre el panel del hilo para que
// el usuario agregue los que quiera. creado_por del hilo es siempre quien
// ejecuta la acción (no el creador original) porque tareas_hilos_insert exige
// creado_por = auth.uid() en su WITH CHECK.
export async function convertirTareaEnHilo(tareaId: string) {
  const supabase = await createClient();
  const usuarioId = await usuarioActualId();

  const { data: original, error: errorOriginal } = await supabase
    .from("tareas")
    .select("titulo, descripcion, visibilidad, proyecto_id, responsable_id")
    .eq("id", tareaId)
    .single();

  if (errorOriginal) return { success: false as const, error: mensajeError(errorOriginal) };

  // id generado en el server: mismo motivo que crearHilo — evita el
  // RETURNING sobre tareas_hilos, cuya policy de SELECT relee la propia tabla.
  const hiloId = crypto.randomUUID();

  const { error: errorHilo } = await supabase.from("tareas_hilos").insert({
    id: hiloId,
    titulo: original.titulo,
    descripcion: original.descripcion,
    visibilidad: original.visibilidad,
    proyecto_id: original.proyecto_id,
    responsable_id: original.responsable_id,
    creado_por: usuarioId,
  });

  if (errorHilo) return { success: false as const, error: mensajeError(errorHilo) };

  const { error: errorMover } = await supabase
    .from("tareas")
    .update({ hilo_id: hiloId, proyecto_id: null })
    .eq("id", tareaId);

  if (errorMover) return { success: false as const, error: mensajeError(errorMover) };

  revalidatePath("/tareas");
  return { success: true as const, hiloId };
}

// §1 spec: "deshacer conversión" siempre disponible. Si el hilo tiene 2+
// tareas o alguna completada, la UI ya mostró la advertencia antes de llamar
// esto — acá se ejecuta el colapso: se conserva la tarea más antigua del
// hilo como tarea suelta (recupera el proyecto_id del hilo) y el resto se
// desactiva (nunca DELETE), igual que cualquier otro registro del sistema.
export async function deshacerConversionHilo(input: DeshacerConversionForm) {
  const parsed = deshacerConversionSchema.safeParse(input);
  if (!parsed.success) {
    return { success: false as const, error: parsed.error.issues[0].message };
  }

  const supabase = await createClient();
  const { hilo_id } = parsed.data;

  const { data: hilo, error: errorHilo } = await supabase
    .from("tareas_hilos")
    .select("proyecto_id")
    .eq("id", hilo_id)
    .single();

  if (errorHilo) return { success: false as const, error: mensajeError(errorHilo) };

  const { data: tareasDelHilo, error: errorTareas } = await supabase
    .from("tareas")
    .select("id")
    .eq("hilo_id", hilo_id)
    .eq("activo", true)
    .order("created_at", { ascending: true });

  if (errorTareas) return { success: false as const, error: mensajeError(errorTareas) };

  const [primera, ...resto] = tareasDelHilo ?? [];

  if (primera) {
    const { error: errorRestaurar } = await supabase
      .from("tareas")
      .update({ hilo_id: null, proyecto_id: hilo.proyecto_id })
      .eq("id", primera.id);

    if (errorRestaurar) return { success: false as const, error: mensajeError(errorRestaurar) };
  }

  if (resto.length > 0) {
    const { error: errorDesactivarResto } = await supabase
      .from("tareas")
      .update({ activo: false })
      .in(
        "id",
        resto.map((t) => t.id)
      );

    if (errorDesactivarResto) return { success: false as const, error: mensajeError(errorDesactivarResto) };
  }

  const { error: errorDesactivarHilo } = await supabase
    .from("tareas_hilos")
    .update({ activo: false })
    .eq("id", hilo_id);

  if (errorDesactivarHilo) return { success: false as const, error: mensajeError(errorDesactivarHilo) };

  revalidatePath("/tareas");
  return { success: true as const };
}

export async function crearProyecto(input: CrearProyectoForm) {
  const parsed = crearProyectoSchema.safeParse(input);
  if (!parsed.success) {
    return { success: false as const, error: parsed.error.issues[0].message };
  }

  const supabase = await createClient();
  const creado_por = await usuarioActualId();
  const { miembros, ...proyecto } = parsed.data;
  // id generado en el server: mismo motivo que crearTarea — un proyecto
  // privado no es visible para su creador hasta que se inserten los miembros.
  const id = crypto.randomUUID();

  const { error } = await supabase.from("tareas_proyectos").insert({ id, ...proyecto, creado_por });

  if (error) return { success: false as const, error: mensajeError(error) };

  const { error: errorMiembros } = await supabase
    .from("tareas_proyectos_miembros")
    .insert(miembros.map((usuario_id) => ({ proyecto_id: id, usuario_id })));

  if (errorMiembros) return { success: false as const, error: mensajeError(errorMiembros) };

  revalidatePath("/tareas/proyectos");
  revalidatePath("/tareas");
  return { success: true as const, id };
}

// Miembros van en el mismo panel que el resto del proyecto: un solo lugar
// donde se modifica todo. El diff (en vez de desactivar-todo-y-reinsertar)
// evita que el trigger que bloquea quitar un miembro con tareas activas se
// dispare también sobre los que quedan.
export async function editarProyecto(input: EditarProyectoForm) {
  const parsed = editarProyectoSchema.safeParse(input);
  if (!parsed.success) {
    return { success: false as const, error: parsed.error.issues[0].message };
  }

  const supabase = await createClient();
  const { id: proyectoId, miembros: usuarioIds, ...proyecto } = parsed.data;

  const { error: errorProyecto } = await supabase
    .from("tareas_proyectos")
    .update(proyecto)
    .eq("id", proyectoId);

  if (errorProyecto) return { success: false as const, error: mensajeError(errorProyecto) };

  const { data: actuales, error: errorLeer } = await supabase
    .from("tareas_proyectos_miembros")
    .select("usuario_id")
    .eq("proyecto_id", proyectoId)
    .eq("activo", true);

  if (errorLeer) return { success: false as const, error: mensajeError(errorLeer) };

  const previos = new Set((actuales ?? []).map((m) => m.usuario_id));
  const quitados = [...previos].filter((id) => !usuarioIds.includes(id));
  const agregados = usuarioIds.filter((id) => !previos.has(id));

  if (quitados.length > 0) {
    const { error: errorDesactivar } = await supabase
      .from("tareas_proyectos_miembros")
      .update({ activo: false })
      .eq("proyecto_id", proyectoId)
      .eq("activo", true)
      .in("usuario_id", quitados);

    if (errorDesactivar) return { success: false as const, error: mensajeError(errorDesactivar) };
  }

  if (agregados.length > 0) {
    const { error: errorInsertar } = await supabase
      .from("tareas_proyectos_miembros")
      .insert(agregados.map((usuario_id) => ({ proyecto_id: proyectoId, usuario_id })));

    if (errorInsertar) return { success: false as const, error: mensajeError(errorInsertar) };
  }

  revalidatePath("/tareas/proyectos");
  revalidatePath("/tareas");
  return { success: true as const };
}

export async function desactivarProyecto(id: string) {
  const supabase = await createClient();
  const { error } = await supabase.from("tareas_proyectos").update({ activo: false }).eq("id", id);
  if (error) return { success: false as const, error: mensajeError(error) };
  revalidatePath("/tareas/proyectos");
  return { success: true as const };
}

export async function crearPlantilla(input: CrearPlantillaForm) {
  const parsed = crearPlantillaSchema.safeParse(input);
  if (!parsed.success) {
    return { success: false as const, error: parsed.error.issues[0].message };
  }

  const supabase = await createClient();
  const creado_por = await usuarioActualId();
  const { items, ...plantilla } = parsed.data;

  const { data, error } = await supabase
    .from("tareas_plantillas")
    .insert({ ...plantilla, creado_por })
    .select("id")
    .single();

  if (error) return { success: false as const, error: mensajeError(error) };

  const { error: errorItems } = await supabase
    .from("tareas_plantillas_items")
    .insert(items.map((item) => ({ plantilla_id: data.id, titulo: item.titulo, orden: item.orden })));

  if (errorItems) return { success: false as const, error: mensajeError(errorItems) };

  revalidatePath("/tareas/plantillas");
  return { success: true as const, id: data.id };
}

// Editar plantilla no toca las tareas ya generadas: agregarTareasDesdePlantilla
// copia los títulos, no referencia los items. Los cambios aplican a usos futuros.
export async function editarPlantilla(input: EditarPlantillaForm) {
  const parsed = editarPlantillaSchema.safeParse(input);
  if (!parsed.success) {
    return { success: false as const, error: parsed.error.issues[0].message };
  }

  const supabase = await createClient();
  const { id, items, ...plantilla } = parsed.data;

  const { error } = await supabase.from("tareas_plantillas").update(plantilla).eq("id", id);
  if (error) return { success: false as const, error: mensajeError(error) };

  const { data: actuales, error: errorActuales } = await supabase
    .from("tareas_plantillas_items")
    .select("id")
    .eq("plantilla_id", id)
    .eq("activo", true);

  if (errorActuales) return { success: false as const, error: mensajeError(errorActuales) };

  const conservados = new Set(items.map((item) => item.id).filter(Boolean));
  const aDesactivar = (actuales ?? []).filter((a) => !conservados.has(a.id)).map((a) => a.id);

  if (aDesactivar.length > 0) {
    const { error: errorDesactivar } = await supabase
      .from("tareas_plantillas_items")
      .update({ activo: false })
      .in("id", aDesactivar);

    if (errorDesactivar) return { success: false as const, error: mensajeError(errorDesactivar) };
  }

  const nuevos = items.filter((item) => !item.id);
  if (nuevos.length > 0) {
    const { error: errorNuevos } = await supabase
      .from("tareas_plantillas_items")
      .insert(nuevos.map((item) => ({ plantilla_id: id, titulo: item.titulo, orden: item.orden })));

    if (errorNuevos) return { success: false as const, error: mensajeError(errorNuevos) };
  }

  // Un update por paso existente: son un puñado por plantilla, no vale armar
  // un upsert con todas las columnas para ahorrar round-trips.
  const existentes = items.filter((item) => item.id);
  const resultados = await Promise.all(
    existentes.map((item) =>
      supabase
        .from("tareas_plantillas_items")
        .update({ titulo: item.titulo, orden: item.orden })
        .eq("id", item.id!),
    ),
  );
  const falla = resultados.find((r) => r.error);
  if (falla?.error) return { success: false as const, error: mensajeError(falla.error) };

  revalidatePath("/tareas/plantillas");
  return { success: true as const };
}

export async function desactivarPlantilla(id: string) {
  const supabase = await createClient();
  const { error } = await supabase.from("tareas_plantillas").update({ activo: false }).eq("id", id);
  if (error) return { success: false as const, error: mensajeError(error) };
  revalidatePath("/tareas/plantillas");
  return { success: true as const };
}

export async function agregarTareasDesdePlantilla(input: AgregarDesdePlantillaForm) {
  const parsed = agregarDesdePlantillaSchema.safeParse(input);
  if (!parsed.success) {
    return { success: false as const, error: parsed.error.issues[0].message };
  }

  const supabase = await createClient();
  const creado_por = await usuarioActualId();
  const { plantilla_id, hilo_id, responsable_id, asignados } = parsed.data;

  const { data: items, error: errorItems } = await supabase
    .from("tareas_plantillas_items")
    .select("titulo, orden")
    .eq("plantilla_id", plantilla_id)
    .eq("activo", true)
    .order("orden");

  if (errorItems) return { success: false as const, error: mensajeError(errorItems) };
  if (!items || items.length === 0) {
    return { success: false as const, error: "La plantilla no tiene pasos" };
  }

  // ids generados en el server: mismo motivo que crearTarea.
  const nuevas = items.map((item) => ({
    id: crypto.randomUUID(),
    titulo: item.titulo,
    hilo_id,
    responsable_id,
    creado_por,
  }));

  const { error: errorInsertar } = await supabase.from("tareas").insert(nuevas);

  if (errorInsertar) return { success: false as const, error: mensajeError(errorInsertar) };

  const { error: errorAsignar } = await supabase
    .from("tareas_asignados")
    .insert(nuevas.flatMap((t) => asignados.map((usuario_id) => ({ tarea_id: t.id, usuario_id }))));

  if (errorAsignar) return { success: false as const, error: mensajeError(errorAsignar) };

  revalidatePath("/tareas");
  return { success: true as const };
}

export async function completarTarea(input: CompletarTareaForm) {
  const parsed = completarTareaSchema.safeParse(input);
  if (!parsed.success) {
    return { success: false as const, error: parsed.error.issues[0].message };
  }

  const supabase = await createClient();
  const { tarea_id, nota_siguiente } = parsed.data;

  const { error } = await supabase
    .from("tareas")
    .update({ estado: "completada", ...(nota_siguiente !== undefined ? { nota_siguiente } : {}) })
    .eq("id", tarea_id);

  if (error) return { success: false as const, error: mensajeError(error) };

  revalidatePath("/tareas");
  return { success: true as const };
}

export async function cambiarEstadoTarea(
  tareaId: string,
  estado: "pendiente" | "en_progreso" | "cancelada"
) {
  const supabase = await createClient();
  const { error } = await supabase.from("tareas").update({ estado }).eq("id", tareaId);
  if (error) return { success: false as const, error: mensajeError(error) };
  revalidatePath("/tareas");
  return { success: true as const };
}

export async function reasignarTarea(input: ReasignarTareaForm) {
  const parsed = reasignarTareaSchema.safeParse(input);
  if (!parsed.success) {
    return { success: false as const, error: parsed.error.issues[0].message };
  }

  const supabase = await createClient();
  const { tarea_id, asignados, responsable_id } = parsed.data;

  const { error: errorResponsable } = await supabase
    .from("tareas")
    .update({ responsable_id })
    .eq("id", tarea_id);

  if (errorResponsable) return { success: false as const, error: mensajeError(errorResponsable) };

  // Desactiva y reinserta en vez de upsert: el índice único de
  // tareas_asignados es parcial (WHERE activo) — el upsert de Supabase no
  // lo soporta (ver GUIDE_DB). Una fila vieja inactiva + una nueva activa
  // para el mismo par no choca contra el índice.
  const { error: errorDesactivar } = await supabase
    .from("tareas_asignados")
    .update({ activo: false })
    .eq("tarea_id", tarea_id)
    .eq("activo", true);

  if (errorDesactivar) return { success: false as const, error: mensajeError(errorDesactivar) };

  const { error: errorAsignar } = await supabase
    .from("tareas_asignados")
    .insert(asignados.map((usuario_id) => ({ tarea_id, usuario_id })));

  if (errorAsignar) return { success: false as const, error: mensajeError(errorAsignar) };

  revalidatePath("/tareas");
  return { success: true as const };
}

export async function posponerTarea(input: PosponerForm) {
  const parsed = posponerSchema.safeParse(input);
  if (!parsed.success) {
    return { success: false as const, error: parsed.error.issues[0].message };
  }

  const supabase = await createClient();
  const { error } = await supabase
    .from("tareas")
    .update({ posponer_desde: hoyISO(), posponer_hasta: parsed.data.hasta })
    .eq("id", parsed.data.id);

  if (error) return { success: false as const, error: mensajeError(error) };

  revalidatePath("/tareas");
  return { success: true as const };
}

export async function posponerHilo(input: PosponerForm) {
  const parsed = posponerSchema.safeParse(input);
  if (!parsed.success) {
    return { success: false as const, error: parsed.error.issues[0].message };
  }

  const supabase = await createClient();
  const { error } = await supabase
    .from("tareas_hilos")
    .update({ posponer_desde: hoyISO(), posponer_hasta: parsed.data.hasta })
    .eq("id", parsed.data.id);

  if (error) return { success: false as const, error: mensajeError(error) };

  revalidatePath("/tareas");
  return { success: true as const };
}

export async function cerrarHilo(input: CerrarHiloForm) {
  const parsed = cerrarHiloSchema.safeParse(input);
  if (!parsed.success) {
    return { success: false as const, error: parsed.error.issues[0].message };
  }

  const supabase = await createClient();
  const { error } = await supabase
    .from("tareas_hilos")
    .update({ estado: "cerrado" })
    .eq("id", parsed.data.hilo_id);

  if (error) return { success: false as const, error: mensajeError(error) };

  revalidatePath("/tareas");
  return { success: true as const };
}

export async function desactivarHilo(id: string) {
  const supabase = await createClient();
  const { error } = await supabase.from("tareas_hilos").update({ activo: false }).eq("id", id);
  if (error) return { success: false as const, error: mensajeError(error) };
  revalidatePath("/tareas");
  return { success: true as const };
}

export async function desactivarTarea(id: string) {
  const supabase = await createClient();
  const { error } = await supabase.from("tareas").update({ activo: false }).eq("id", id);
  if (error) return { success: false as const, error: mensajeError(error) };
  revalidatePath("/tareas");
  return { success: true as const };
}

export async function asociarTareaHilo(tareaId: string, hiloId: string) {
  const supabase = await createClient();
  const { error } = await supabase
    .from("tareas")
    .update({ hilo_id: hiloId, proyecto_id: null })
    .eq("id", tareaId);
  if (error) return { success: false as const, error: mensajeError(error) };
  revalidatePath("/tareas");
  return { success: true as const };
}

export async function desasociarTareaHilo(tareaId: string) {
  const supabase = await createClient();
  const { error } = await supabase.from("tareas").update({ hilo_id: null }).eq("id", tareaId);
  if (error) return { success: false as const, error: mensajeError(error) };
  revalidatePath("/tareas");
  return { success: true as const };
}

export async function actualizarTemperatura(tareaId: string, temperatura: number) {
  if (!Number.isInteger(temperatura) || temperatura < 1 || temperatura > 100) {
    return { success: false as const, error: "Temperatura fuera de rango" };
  }
  const supabase = await createClient();
  const { error } = await supabase.from("tareas").update({ temperatura }).eq("id", tareaId);
  if (error) return { success: false as const, error: mensajeError(error) };
  revalidatePath("/tareas");
  return { success: true as const };
}

// Notas: historial que acumula (nunca se pisan) — "agregar", no "editar".
// listarNotas* son lecturas pero viven acá (no en queries.ts) porque
// NotasSection.tsx es un Client Component: solo una función "use server"
// es invocable por RPC desde ahí, queries.ts no lo es.
export async function agregarNotaTarea(input: AgregarNotaTareaForm) {
  const parsed = agregarNotaTareaSchema.safeParse(input);
  if (!parsed.success) {
    return { success: false as const, error: parsed.error.issues[0].message };
  }

  const supabase = await createClient();
  const usuario_id = await usuarioActualId();
  const { error } = await supabase.from("tareas_notas").insert({ ...parsed.data, usuario_id });
  if (error) return { success: false as const, error: mensajeError(error) };

  revalidatePath("/tareas");
  return { success: true as const };
}

export async function agregarNotaHilo(input: AgregarNotaHiloForm) {
  const parsed = agregarNotaHiloSchema.safeParse(input);
  if (!parsed.success) {
    return { success: false as const, error: parsed.error.issues[0].message };
  }

  const supabase = await createClient();
  const usuario_id = await usuarioActualId();
  const { error } = await supabase.from("tareas_hilos_notas").insert({ ...parsed.data, usuario_id });
  if (error) return { success: false as const, error: mensajeError(error) };

  revalidatePath("/tareas");
  return { success: true as const };
}

export async function listarNotasTarea(tareaId: string) {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("tareas_notas")
    .select("id, tarea_id, usuario_id, nota, created_at, usuarios(nombre)")
    .eq("tarea_id", tareaId)
    .eq("activo", true)
    .order("created_at", { ascending: false });

  if (error) return { success: false as const, error: mensajeError(error) };
  return { success: true as const, data: (data ?? []) as TareaNota[] };
}

export async function listarNotasHilo(hiloId: string) {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("tareas_hilos_notas")
    .select("id, hilo_id, usuario_id, nota, created_at, usuarios(nombre)")
    .eq("hilo_id", hiloId)
    .eq("activo", true)
    .order("created_at", { ascending: false });

  if (error) return { success: false as const, error: mensajeError(error) };
  return { success: true as const, data: (data ?? []) as HiloNota[] };
}
