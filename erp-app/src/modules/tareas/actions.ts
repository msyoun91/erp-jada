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
  marcarTutorialSchema,
  uuidSchema,
  cambiarEstadoTareaSchema,
  asociarTareaHiloSchema,
  temperaturaSchema,
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

type Cliente = Awaited<ReturnType<typeof createClient>>;

const SIN_FILAS = "No se pudo guardar: el registro ya no existe o no tenés permiso para modificarlo";

// Un UPDATE que RLS rechaza no falla: afecta 0 filas y vuelve sin error, así que
// la action devolvía success sobre un cambio que nunca ocurrió. Se usa en los
// updates que apuntan a filas puntuales; donde 0 filas es un resultado legítimo
// (la cascada de un hilo sin tareas) se sigue mirando solo `error`.
function errorDeUpdate({ error, count }: { error: unknown; count: number | null }) {
  if (error) return mensajeError(error);
  return count === 0 ? SIN_FILAS : null;
}

// Único escritor de tareas_asignados sobre una tarea que ya existe: lo usan
// editarTarea y reasignarTarea. Devuelve el mensaje de error, o null si salió bien.
//
// Si el conjunto no cambió no toca nada: editar el título de una tarea no debe
// reescribir sus asignaciones, y sin ese corte quien no tiene `tareas_asignar`
// no podría guardar ningún cambio en una tarea compartida (los asignados
// viajan igual como defaults ocultos, y reinsertarlos choca contra la policy).
async function sincronizarAsignados(supabase: Cliente, tarea_id: string, asignados: string[]) {
  const { data: actuales, error } = await supabase
    .from("tareas_asignados")
    .select("usuario_id")
    .eq("tarea_id", tarea_id)
    .eq("activo", true);

  if (error) return mensajeError(error);

  const previos = (actuales ?? []).map((a) => a.usuario_id);
  if (previos.length === asignados.length && previos.every((id) => asignados.includes(id))) {
    return null;
  }

  // Desactiva y reinserta en vez de upsert: el índice único de
  // tareas_asignados es parcial (WHERE activo) — el upsert de Supabase no
  // lo soporta (ver GUIDE_DB). Una fila vieja inactiva + una nueva activa
  // para el mismo par no choca contra el índice.
  if (previos.length > 0) {
    const fallo = errorDeUpdate(
      await supabase
        .from("tareas_asignados")
        .update({ activo: false }, { count: "exact" })
        .eq("tarea_id", tarea_id)
        .eq("activo", true),
    );

    if (fallo) return fallo;
  }

  const { error: errorAsignar } = await supabase
    .from("tareas_asignados")
    .insert(asignados.map((usuario_id) => ({ tarea_id, usuario_id })));

  return errorAsignar ? mensajeError(errorAsignar) : null;
}

export async function crearTarea(input: CrearTareaForm) {
  const parsed = crearTareaSchema.safeParse(input);
  if (!parsed.success) {
    return { success: false as const, error: parsed.error.issues[0].message };
  }

  const supabase = await createClient();
  const d = parsed.data;

  const { data: id, error } = await supabase.rpc("crear_tarea", {
    p_titulo: d.titulo,
    p_descripcion: d.descripcion ?? null,
    p_hilo_id: d.hilo_id,
    p_proyecto_id: d.proyecto_id,
    p_paso_anterior_id: d.paso_anterior_id,
    p_visibilidad: d.visibilidad,
    p_responsable_id: d.responsable_id,
    p_asignados: d.asignados,
    p_fecha_vencimiento: d.fecha_vencimiento,
    p_temperatura: d.temperatura,
    p_recurrencia_cantidad: d.recurrencia_cantidad ?? null,
    p_recurrencia_unidad: d.recurrencia_unidad ?? null,
    p_modo_completado: d.modo_completado,
    p_origen_app: d.origen_app ?? null,
    p_origen_punto: d.origen_punto ?? null,
  });

  if (error) return { success: false as const, error: mensajeError(error) };

  revalidatePath("/tareas");
  return { success: true as const, id };
}

export async function editarTarea(input: EditarTareaForm) {
  const parsed = editarTareaSchema.safeParse(input);
  if (!parsed.success) {
    return { success: false as const, error: parsed.error.issues[0].message };
  }

  const supabase = await createClient();
  const { id, asignados, ...campos } = parsed.data;

  const fallo = errorDeUpdate(
    await supabase.from("tareas").update(campos, { count: "exact" }).eq("id", id),
  );
  if (fallo) return { success: false as const, error: fallo };

  const falloAsignados = await sincronizarAsignados(supabase, id, asignados);
  if (falloAsignados) return { success: false as const, error: falloAsignados };

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

  const fallo = errorDeUpdate(
    await supabase.from("tareas_hilos").update(campos, { count: "exact" }).eq("id", id),
  );
  if (fallo) return { success: false as const, error: fallo };

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
  const parsed = uuidSchema.safeParse(tareaId);
  if (!parsed.success) {
    return { success: false as const, error: parsed.error.issues[0].message };
  }

  const supabase = await createClient();

  const { data: hiloId, error } = await supabase.rpc("convertir_tarea_en_hilo", {
    p_tarea_id: parsed.data,
  });

  if (error) return { success: false as const, error: mensajeError(error) };

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

  const { error } = await supabase.rpc("deshacer_conversion_hilo", {
    p_hilo_id: parsed.data.hilo_id,
  });

  if (error) return { success: false as const, error: mensajeError(error) };

  revalidatePath("/tareas");
  return { success: true as const };
}

export async function crearProyecto(input: CrearProyectoForm) {
  const parsed = crearProyectoSchema.safeParse(input);
  if (!parsed.success) {
    return { success: false as const, error: parsed.error.issues[0].message };
  }

  const supabase = await createClient();
  const d = parsed.data;

  const { data: id, error } = await supabase.rpc("crear_proyecto", {
    p_nombre: d.nombre,
    p_descripcion: d.descripcion ?? null,
    p_visibilidad: d.visibilidad,
    p_miembros: d.miembros,
  });

  if (error) return { success: false as const, error: mensajeError(error) };

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

  const falloProyecto = errorDeUpdate(
    await supabase
      .from("tareas_proyectos")
      .update(proyecto, { count: "exact" })
      .eq("id", proyectoId),
  );

  if (falloProyecto) return { success: false as const, error: falloProyecto };

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
    const falloQuitar = errorDeUpdate(
      await supabase
        .from("tareas_proyectos_miembros")
        .update({ activo: false }, { count: "exact" })
        .eq("proyecto_id", proyectoId)
        .eq("activo", true)
        .in("usuario_id", quitados),
    );

    if (falloQuitar) return { success: false as const, error: falloQuitar };
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
  const parsed = uuidSchema.safeParse(id);
  if (!parsed.success) {
    return { success: false as const, error: parsed.error.issues[0].message };
  }

  const supabase = await createClient();
  const fallo = errorDeUpdate(
    await supabase
      .from("tareas_proyectos")
      .update({ activo: false }, { count: "exact" })
      .eq("id", parsed.data),
  );
  if (fallo) return { success: false as const, error: fallo };
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

  const fallo = errorDeUpdate(
    await supabase.from("tareas_plantillas").update(plantilla, { count: "exact" }).eq("id", id),
  );
  if (fallo) return { success: false as const, error: fallo };

  const { data: actuales, error: errorActuales } = await supabase
    .from("tareas_plantillas_items")
    .select("id")
    .eq("plantilla_id", id)
    .eq("activo", true);

  if (errorActuales) return { success: false as const, error: mensajeError(errorActuales) };

  const conservados = new Set(items.map((item) => item.id).filter(Boolean));
  const aDesactivar = (actuales ?? []).filter((a) => !conservados.has(a.id)).map((a) => a.id);

  if (aDesactivar.length > 0) {
    const falloDesactivar = errorDeUpdate(
      await supabase
        .from("tareas_plantillas_items")
        .update({ activo: false }, { count: "exact" })
        .in("id", aDesactivar),
    );

    if (falloDesactivar) return { success: false as const, error: falloDesactivar };
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
        .update({ titulo: item.titulo, orden: item.orden }, { count: "exact" })
        .eq("id", item.id!),
    ),
  );
  const falloItem = resultados.map((r) => errorDeUpdate(r)).find(Boolean);
  if (falloItem) return { success: false as const, error: falloItem };

  revalidatePath("/tareas/plantillas");
  return { success: true as const };
}

export async function desactivarPlantilla(id: string) {
  const parsed = uuidSchema.safeParse(id);
  if (!parsed.success) {
    return { success: false as const, error: parsed.error.issues[0].message };
  }

  const supabase = await createClient();
  const fallo = errorDeUpdate(
    await supabase
      .from("tareas_plantillas")
      .update({ activo: false }, { count: "exact" })
      .eq("id", parsed.data),
  );
  if (fallo) return { success: false as const, error: fallo };
  revalidatePath("/tareas/plantillas");
  return { success: true as const };
}

export async function agregarTareasDesdePlantilla(input: AgregarDesdePlantillaForm) {
  const parsed = agregarDesdePlantillaSchema.safeParse(input);
  if (!parsed.success) {
    return { success: false as const, error: parsed.error.issues[0].message };
  }

  const supabase = await createClient();
  const { plantilla_id, hilo_id, responsable_id, asignados } = parsed.data;

  const { error } = await supabase.rpc("agregar_tareas_desde_plantilla", {
    p_plantilla_id: plantilla_id,
    p_hilo_id: hilo_id,
    p_responsable_id: responsable_id,
    p_asignados: asignados,
  });

  if (error) return { success: false as const, error: mensajeError(error) };

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

  const fallo = errorDeUpdate(
    await supabase
      .from("tareas")
      .update(
        { estado: "completada", ...(nota_siguiente !== undefined ? { nota_siguiente } : {}) },
        { count: "exact" },
      )
      .eq("id", tarea_id),
  );

  if (fallo) return { success: false as const, error: fallo };

  revalidatePath("/tareas");
  return { success: true as const };
}

export async function cambiarEstadoTarea(
  tareaId: string,
  estado: "pendiente" | "en_progreso" | "cancelada"
) {
  const parsed = cambiarEstadoTareaSchema.safeParse({ tarea_id: tareaId, estado });
  if (!parsed.success) {
    return { success: false as const, error: parsed.error.issues[0].message };
  }

  const supabase = await createClient();
  const fallo = errorDeUpdate(
    await supabase
      .from("tareas")
      .update({ estado: parsed.data.estado }, { count: "exact" })
      .eq("id", parsed.data.tarea_id),
  );
  if (fallo) return { success: false as const, error: fallo };
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

  const falloResponsable = errorDeUpdate(
    await supabase
      .from("tareas")
      .update({ responsable_id }, { count: "exact" })
      .eq("id", tarea_id),
  );

  if (falloResponsable) return { success: false as const, error: falloResponsable };

  const falloAsignar = await sincronizarAsignados(supabase, tarea_id, asignados);
  if (falloAsignar) return { success: false as const, error: falloAsignar };

  revalidatePath("/tareas");
  return { success: true as const };
}

export async function posponerTarea(input: PosponerForm) {
  const parsed = posponerSchema.safeParse(input);
  if (!parsed.success) {
    return { success: false as const, error: parsed.error.issues[0].message };
  }

  const supabase = await createClient();
  const fallo = errorDeUpdate(
    await supabase
      .from("tareas")
      .update({ posponer_desde: hoyISO(), posponer_hasta: parsed.data.hasta }, { count: "exact" })
      .eq("id", parsed.data.id),
  );

  if (fallo) return { success: false as const, error: fallo };

  revalidatePath("/tareas");
  return { success: true as const };
}

export async function posponerHilo(input: PosponerForm) {
  const parsed = posponerSchema.safeParse(input);
  if (!parsed.success) {
    return { success: false as const, error: parsed.error.issues[0].message };
  }

  const supabase = await createClient();
  const fallo = errorDeUpdate(
    await supabase
      .from("tareas_hilos")
      .update({ posponer_desde: hoyISO(), posponer_hasta: parsed.data.hasta }, { count: "exact" })
      .eq("id", parsed.data.id),
  );

  if (fallo) return { success: false as const, error: fallo };

  revalidatePath("/tareas");
  return { success: true as const };
}

export async function cerrarHilo(input: CerrarHiloForm) {
  const parsed = cerrarHiloSchema.safeParse(input);
  if (!parsed.success) {
    return { success: false as const, error: parsed.error.issues[0].message };
  }

  const supabase = await createClient();
  const fallo = errorDeUpdate(
    await supabase
      .from("tareas_hilos")
      .update({ estado: "cerrado" }, { count: "exact" })
      .eq("id", parsed.data.hilo_id),
  );

  if (fallo) return { success: false as const, error: fallo };

  revalidatePath("/tareas");
  return { success: true as const };
}

export async function desactivarHilo(id: string) {
  const parsed = uuidSchema.safeParse(id);
  if (!parsed.success) {
    return { success: false as const, error: parsed.error.issues[0].message };
  }

  const supabase = await createClient();
  // Las tareas caen con el hilo. Sin esto quedan activas apuntando a un hilo
  // que las queries ya no traen: la lista las agrupa por hilo y no son
  // sueltas, así que desaparecen de la UI aunque RLS siga devolviéndolas.
  const { error } = await supabase.rpc("desactivar_hilo", { p_hilo_id: parsed.data });

  if (error) return { success: false as const, error: mensajeError(error) };
  revalidatePath("/tareas");
  return { success: true as const };
}

export async function desactivarTarea(id: string) {
  const parsed = uuidSchema.safeParse(id);
  if (!parsed.success) {
    return { success: false as const, error: parsed.error.issues[0].message };
  }

  const supabase = await createClient();
  const fallo = errorDeUpdate(
    await supabase.from("tareas").update({ activo: false }, { count: "exact" }).eq("id", parsed.data),
  );
  if (fallo) return { success: false as const, error: fallo };
  revalidatePath("/tareas");
  return { success: true as const };
}

export async function asociarTareaHilo(tareaId: string, hiloId: string) {
  const parsed = asociarTareaHiloSchema.safeParse({ tarea_id: tareaId, hilo_id: hiloId });
  if (!parsed.success) {
    return { success: false as const, error: parsed.error.issues[0].message };
  }

  const supabase = await createClient();
  const fallo = errorDeUpdate(
    await supabase
      .from("tareas")
      .update({ hilo_id: parsed.data.hilo_id, proyecto_id: null }, { count: "exact" })
      .eq("id", parsed.data.tarea_id),
  );
  if (fallo) return { success: false as const, error: fallo };
  revalidatePath("/tareas");
  return { success: true as const };
}

export async function desasociarTareaHilo(tareaId: string) {
  const parsed = uuidSchema.safeParse(tareaId);
  if (!parsed.success) {
    return { success: false as const, error: parsed.error.issues[0].message };
  }

  const supabase = await createClient();
  const fallo = errorDeUpdate(
    await supabase.from("tareas").update({ hilo_id: null }, { count: "exact" }).eq("id", parsed.data),
  );
  if (fallo) return { success: false as const, error: fallo };
  revalidatePath("/tareas");
  return { success: true as const };
}

export async function actualizarTemperatura(tareaId: string, temperatura: number) {
  const parsed = temperaturaSchema.safeParse({ tarea_id: tareaId, temperatura });
  if (!parsed.success) {
    return { success: false as const, error: parsed.error.issues[0].message };
  }

  const supabase = await createClient();
  const fallo = errorDeUpdate(
    await supabase
      .from("tareas")
      .update({ temperatura: parsed.data.temperatura }, { count: "exact" })
      .eq("id", parsed.data.tarea_id),
  );
  if (fallo) return { success: false as const, error: fallo };
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
  const parsed = uuidSchema.safeParse(tareaId);
  if (!parsed.success) {
    return { success: false as const, error: parsed.error.issues[0].message };
  }

  const supabase = await createClient();
  const { data, error } = await supabase
    .from("tareas_notas")
    .select("id, tarea_id, usuario_id, nota, created_at, usuarios(nombre)")
    .eq("tarea_id", parsed.data)
    .eq("activo", true)
    .order("created_at", { ascending: false });

  if (error) return { success: false as const, error: mensajeError(error) };
  return { success: true as const, data: (data ?? []) as TareaNota[] };
}

export async function listarNotasHilo(hiloId: string) {
  const parsed = uuidSchema.safeParse(hiloId);
  if (!parsed.success) {
    return { success: false as const, error: parsed.error.issues[0].message };
  }

  const supabase = await createClient();
  const { data, error } = await supabase
    .from("tareas_hilos_notas")
    .select("id, hilo_id, usuario_id, nota, created_at, usuarios(nombre)")
    .eq("hilo_id", parsed.data)
    .eq("activo", true)
    .order("created_at", { ascending: false });

  if (error) return { success: false as const, error: mensajeError(error) };
  return { success: true as const, data: (data ?? []) as HiloNota[] };
}

// Sin `revalidatePath`: los pasos vistos solo se leen al montar el layout, y
// el cliente ya sabe cuáles marcó. Revalidar acá volvería a renderizar la
// vista entera para no cambiar un pixel.
export async function marcarTutorialVisto(pasos: string[]) {
  const parsed = marcarTutorialSchema.safeParse({ pasos });
  if (!parsed.success) return { success: false as const, error: "Datos inválidos" };

  const supabase = await createClient();
  const usuario_id = await usuarioActualId();
  const { error } = await supabase
    .from("usuario_tutorial")
    .upsert(
      parsed.data.pasos.map((paso) => ({ usuario_id, paso })),
      { onConflict: "usuario_id,paso" },
    );

  if (error) return { success: false as const, error: mensajeError(error) };
  return { success: true as const };
}
