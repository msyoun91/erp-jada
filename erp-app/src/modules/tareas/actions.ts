"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { hoyISO } from "@/lib/utils";
import {
  crearTareaSchema,
  crearHiloSchema,
  crearProyectoSchema,
  crearPlantillaSchema,
  reasignarTareaSchema,
  posponerSchema,
  completarTareaSchema,
  cerrarHiloSchema,
  agregarDesdePlantillaSchema,
  agregarPasoSchema,
  deshacerConversionSchema,
  agregarNotaTareaSchema,
  agregarNotaHiloSchema,
  type CrearTareaForm,
  type CrearHiloForm,
  type CrearProyectoForm,
  type CrearPlantillaForm,
  type ReasignarTareaForm,
  type PosponerForm,
  type CompletarTareaForm,
  type CerrarHiloForm,
  type AgregarDesdePlantillaForm,
  type AgregarPasoForm,
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

  const { data, error } = await supabase
    .from("tareas")
    .insert({ ...tarea, creado_por })
    .select("id")
    .single();

  if (error) return { success: false as const, error: error.message };

  const { error: errorAsignados } = await supabase
    .from("tareas_asignados")
    .insert(asignados.map((usuario_id) => ({ tarea_id: data.id, usuario_id })));

  if (errorAsignados) return { success: false as const, error: errorAsignados.message };

  revalidatePath("/tareas");
  return { success: true as const, id: data.id };
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

  if (error) return { success: false as const, error: error.message };

  revalidatePath("/tareas");
  return { success: true as const, id };
}

// §1 spec: una tarea suelta se convierte en hilo recién al agregarle un 2do
// paso — no hay pantalla de "convertir", el cambio de estructura es real.
// creado_por del hilo/paso nuevo es siempre quien ejecuta la acción (no el
// creador original) porque tareas_hilos_insert/tareas_insert exigen
// creado_por = auth.uid() en su WITH CHECK.
export async function agregarPasoATarea(input: AgregarPasoForm) {
  const parsed = agregarPasoSchema.safeParse(input);
  if (!parsed.success) {
    return { success: false as const, error: parsed.error.issues[0].message };
  }

  const supabase = await createClient();
  const usuarioId = await usuarioActualId();
  const { tarea_id, titulo_paso } = parsed.data;

  const { data: original, error: errorOriginal } = await supabase
    .from("tareas")
    .select("titulo, descripcion, visibilidad, proyecto_id, responsable_id")
    .eq("id", tarea_id)
    .single();

  if (errorOriginal) return { success: false as const, error: errorOriginal.message };

  const { data: asignados, error: errorAsignados } = await supabase
    .from("tareas_asignados")
    .select("usuario_id")
    .eq("tarea_id", tarea_id)
    .eq("activo", true);

  if (errorAsignados) return { success: false as const, error: errorAsignados.message };

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

  if (errorHilo) return { success: false as const, error: errorHilo.message };

  const { error: errorMoverOriginal } = await supabase
    .from("tareas")
    .update({ hilo_id: hiloId, proyecto_id: null })
    .eq("id", tarea_id);

  if (errorMoverOriginal) return { success: false as const, error: errorMoverOriginal.message };

  const { data: nuevoPaso, error: errorPaso } = await supabase
    .from("tareas")
    .insert({
      titulo: titulo_paso,
      hilo_id: hiloId,
      responsable_id: original.responsable_id,
      creado_por: usuarioId,
      visibilidad: original.visibilidad,
    })
    .select("id")
    .single();

  if (errorPaso) return { success: false as const, error: errorPaso.message };

  if (asignados && asignados.length > 0) {
    const { error: errorAsignar } = await supabase
      .from("tareas_asignados")
      .insert(asignados.map((a) => ({ tarea_id: nuevoPaso.id, usuario_id: a.usuario_id })));

    if (errorAsignar) return { success: false as const, error: errorAsignar.message };
  }

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

  if (errorHilo) return { success: false as const, error: errorHilo.message };

  const { data: tareasDelHilo, error: errorTareas } = await supabase
    .from("tareas")
    .select("id")
    .eq("hilo_id", hilo_id)
    .eq("activo", true)
    .order("created_at", { ascending: true });

  if (errorTareas) return { success: false as const, error: errorTareas.message };

  const [primera, ...resto] = tareasDelHilo ?? [];

  if (primera) {
    const { error: errorRestaurar } = await supabase
      .from("tareas")
      .update({ hilo_id: null, proyecto_id: hilo.proyecto_id })
      .eq("id", primera.id);

    if (errorRestaurar) return { success: false as const, error: errorRestaurar.message };
  }

  if (resto.length > 0) {
    const { error: errorDesactivarResto } = await supabase
      .from("tareas")
      .update({ activo: false })
      .in(
        "id",
        resto.map((t) => t.id)
      );

    if (errorDesactivarResto) return { success: false as const, error: errorDesactivarResto.message };
  }

  const { error: errorDesactivarHilo } = await supabase
    .from("tareas_hilos")
    .update({ activo: false })
    .eq("id", hilo_id);

  if (errorDesactivarHilo) return { success: false as const, error: errorDesactivarHilo.message };

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

  const { data, error } = await supabase
    .from("tareas_proyectos")
    .insert({ ...proyecto, creado_por })
    .select("id")
    .single();

  if (error) return { success: false as const, error: error.message };

  if (miembros && miembros.length > 0) {
    const { error: errorMiembros } = await supabase
      .from("tareas_proyectos_miembros")
      .insert(miembros.map((usuario_id) => ({ proyecto_id: data.id, usuario_id })));

    if (errorMiembros) return { success: false as const, error: errorMiembros.message };
  }

  revalidatePath("/tareas/proyectos");
  return { success: true as const, id: data.id };
}

export async function gestionarMiembrosProyecto(proyectoId: string, usuarioIds: string[]) {
  const supabase = await createClient();

  const { error: errorDesactivar } = await supabase
    .from("tareas_proyectos_miembros")
    .update({ activo: false })
    .eq("proyecto_id", proyectoId)
    .eq("activo", true);

  if (errorDesactivar) return { success: false as const, error: errorDesactivar.message };

  if (usuarioIds.length > 0) {
    const { error: errorInsertar } = await supabase
      .from("tareas_proyectos_miembros")
      .insert(usuarioIds.map((usuario_id) => ({ proyecto_id: proyectoId, usuario_id })));

    if (errorInsertar) return { success: false as const, error: errorInsertar.message };
  }

  revalidatePath("/tareas/proyectos");
  return { success: true as const };
}

export async function desactivarProyecto(id: string) {
  const supabase = await createClient();
  const { error } = await supabase.from("tareas_proyectos").update({ activo: false }).eq("id", id);
  if (error) return { success: false as const, error: error.message };
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

  if (error) return { success: false as const, error: error.message };

  const { error: errorItems } = await supabase
    .from("tareas_plantillas_items")
    .insert(items.map((item) => ({ plantilla_id: data.id, titulo: item.titulo, orden: item.orden })));

  if (errorItems) return { success: false as const, error: errorItems.message };

  revalidatePath("/tareas/plantillas");
  return { success: true as const, id: data.id };
}

export async function desactivarPlantilla(id: string) {
  const supabase = await createClient();
  const { error } = await supabase.from("tareas_plantillas").update({ activo: false }).eq("id", id);
  if (error) return { success: false as const, error: error.message };
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

  if (errorItems) return { success: false as const, error: errorItems.message };
  if (!items || items.length === 0) {
    return { success: false as const, error: "La plantilla no tiene pasos" };
  }

  const { data: tareasCreadas, error: errorInsertar } = await supabase
    .from("tareas")
    .insert(
      items.map((item) => ({
        titulo: item.titulo,
        hilo_id,
        responsable_id,
        creado_por,
      }))
    )
    .select("id");

  if (errorInsertar) return { success: false as const, error: errorInsertar.message };

  const { error: errorAsignar } = await supabase
    .from("tareas_asignados")
    .insert((tareasCreadas ?? []).flatMap((t) => asignados.map((usuario_id) => ({ tarea_id: t.id, usuario_id }))));

  if (errorAsignar) return { success: false as const, error: errorAsignar.message };

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

  if (error) return { success: false as const, error: error.message };

  revalidatePath("/tareas");
  return { success: true as const };
}

export async function cambiarEstadoTarea(
  tareaId: string,
  estado: "pendiente" | "en_progreso" | "cancelada"
) {
  const supabase = await createClient();
  const { error } = await supabase.from("tareas").update({ estado }).eq("id", tareaId);
  if (error) return { success: false as const, error: error.message };
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

  if (errorResponsable) return { success: false as const, error: errorResponsable.message };

  // Desactiva y reinserta en vez de upsert: el índice único de
  // tareas_asignados es parcial (WHERE activo) — el upsert de Supabase no
  // lo soporta (ver GUIDE_DB). Una fila vieja inactiva + una nueva activa
  // para el mismo par no choca contra el índice.
  const { error: errorDesactivar } = await supabase
    .from("tareas_asignados")
    .update({ activo: false })
    .eq("tarea_id", tarea_id)
    .eq("activo", true);

  if (errorDesactivar) return { success: false as const, error: errorDesactivar.message };

  const { error: errorAsignar } = await supabase
    .from("tareas_asignados")
    .insert(asignados.map((usuario_id) => ({ tarea_id, usuario_id })));

  if (errorAsignar) return { success: false as const, error: errorAsignar.message };

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

  if (error) return { success: false as const, error: error.message };

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

  if (error) return { success: false as const, error: error.message };

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

  if (error) return { success: false as const, error: error.message };

  revalidatePath("/tareas");
  return { success: true as const };
}

export async function desactivarHilo(id: string) {
  const supabase = await createClient();
  const { error } = await supabase.from("tareas_hilos").update({ activo: false }).eq("id", id);
  if (error) return { success: false as const, error: error.message };
  revalidatePath("/tareas");
  return { success: true as const };
}

export async function desactivarTarea(id: string) {
  const supabase = await createClient();
  const { error } = await supabase.from("tareas").update({ activo: false }).eq("id", id);
  if (error) return { success: false as const, error: error.message };
  revalidatePath("/tareas");
  return { success: true as const };
}

export async function asociarTareaHilo(tareaId: string, hiloId: string) {
  const supabase = await createClient();
  const { error } = await supabase
    .from("tareas")
    .update({ hilo_id: hiloId, proyecto_id: null })
    .eq("id", tareaId);
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

export async function actualizarTemperatura(tareaId: string, temperatura: number) {
  if (!Number.isInteger(temperatura) || temperatura < 1 || temperatura > 100) {
    return { success: false as const, error: "Temperatura fuera de rango" };
  }
  const supabase = await createClient();
  const { error } = await supabase.from("tareas").update({ temperatura }).eq("id", tareaId);
  if (error) return { success: false as const, error: error.message };
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
  if (error) return { success: false as const, error: error.message };

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
  if (error) return { success: false as const, error: error.message };

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

  if (error) return { success: false as const, error: error.message };
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

  if (error) return { success: false as const, error: error.message };
  return { success: true as const, data: (data ?? []) as HiloNota[] };
}
