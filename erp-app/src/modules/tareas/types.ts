import { z } from "zod";
import type { Tables } from "@/lib/supabase/database.types";

export type Tarea = Tables<"tareas">;
export type TareaHilo = Tables<"tareas_hilos">;
export type TareaProyecto = Tables<"tareas_proyectos">;
export type TareaAsignado = Tables<"tareas_asignados">;
export type TareaProyectoMiembro = Tables<"tareas_proyectos_miembros">;
export type TareaPlantilla = Tables<"tareas_plantillas">;
export type TareaPlantillaItem = Tables<"tareas_plantillas_items">;
export type TareaEvento = Tables<"tareas_eventos">;

export type Usuario = { id: string; nombre: string };
type UsuarioNombre = { nombre: string };

export type TareaConAsignados = Tarea & {
  tareas_asignados: { usuario_id: string; activo: boolean; usuarios: UsuarioNombre | null }[];
  // Precargadas por getListaTareas — con las notas visibles por defecto en
  // cada panel de tarea, pedirlas de a una desde el cliente serían N requests.
  tareas_notas?: TareaNota[];
};

export type EventoAuditoria = {
  id: string;
  tarea_id: string;
  usuario_id: string | null;
  created_at: string;
  fecha_asignacion: string | null;
  tareas: { titulo: string; created_at: string } | null;
  usuarios: UsuarioNombre | null;
};

export type TareaPendiente = {
  id: string;
  titulo: string;
  estado: string;
  fecha_vencimiento: string | null;
  hilo_titulo: string | null;
};

export type TareaNota = {
  id: string;
  tarea_id: string;
  usuario_id: string;
  nota: string;
  created_at: string;
  usuarios: UsuarioNombre | null;
};

export type HiloNota = {
  id: string;
  hilo_id: string;
  usuario_id: string;
  nota: string;
  created_at: string;
  usuarios: UsuarioNombre | null;
};

// Un <input type="date"> vacío manda "" — Postgres rechaza "" para columnas
// date. Normaliza a null en el schema, no en cada action.
const fechaOpcional = z
  .string()
  .nullish()
  .transform((v) => v || null);

// Un <select> con opción "Sin proyecto" manda "" — normaliza a null antes de
// validar uuid (mismo motivo que fechaOpcional).
const uuidOpcional = z
  .union([z.string().uuid(), z.literal(""), z.null(), z.undefined()])
  .transform((v) => v || null);

// Campos comunes a crear y editar (estado/temperatura tienen su propia
// action) — base de crearTareaSchema y editarTareaSchema, para no duplicar
// validadores.
const tareaEditableSchema = z.object({
  titulo: z.string().min(1, "El título es obligatorio").max(200),
  descripcion: z.string().max(2000).optional(),
  proyecto_id: uuidOpcional,
  visibilidad: z.enum(["publico", "privado"]).default("privado"),
  fecha_vencimiento: fechaOpcional,
  temperatura: z.coerce.number().int().min(1).max(100).default(50),
  recurrencia_cantidad: z.coerce.number().int().positive().nullish(),
  recurrencia_unidad: z.enum(["dia", "mes"]).nullish(),
});

const recurrenciaCompleta = (d: {
  recurrencia_cantidad?: number | null;
  recurrencia_unidad?: "dia" | "mes" | null;
}) => (d.recurrencia_cantidad == null) === (d.recurrencia_unidad == null);

export const crearTareaSchema = tareaEditableSchema
  .extend({
    hilo_id: uuidOpcional,
    // Presente = "crear siguiente paso": la tarea nace bloqueada hasta que la
    // previa esté completada. No aparece en editarTareaSchema porque es
    // inmutable después del INSERT (sql/017) — esa inmutabilidad es lo que
    // vuelve imposible un ciclo sin recorrer la cadena.
    paso_anterior_id: uuidOpcional,
    responsable_id: z.string().uuid(),
    asignados: z.array(z.string().uuid()).min(1, "Debe haber al menos un asignado"),
    modo_completado: z.enum(["manual", "automatico", "hibrido"]).default("manual"),
    origen_app: z.string().max(100).optional(),
    origen_punto: z.string().max(500).optional(),
  })
  .refine((d) => !(d.hilo_id && d.proyecto_id), {
    message: "Una tarea con hilo no lleva proyecto propio — lo hereda del hilo",
    path: ["proyecto_id"],
  })
  .refine((d) => !d.paso_anterior_id || !!d.hilo_id, {
    message: "Un paso vive dentro de un hilo — de ahí sale su visibilidad",
    path: ["hilo_id"],
  })
  .refine((d) => !(d.paso_anterior_id && d.recurrencia_cantidad), {
    message: "Un paso de una cadena no puede ser recurrente",
    path: ["recurrencia_cantidad"],
  })
  .refine(recurrenciaCompleta, {
    message: "Cantidad y unidad de recurrencia van juntas",
    path: ["recurrencia_unidad"],
  })
  .refine((d) => d.asignados.includes(d.responsable_id), {
    message: "El responsable debe estar entre los asignados",
    path: ["responsable_id"],
  });

export type CrearTareaForm = z.input<typeof crearTareaSchema>;
export type CrearTareaValues = z.output<typeof crearTareaSchema>;

// Editar cambia también los asignados: el panel de edición muestra el mismo
// picker que el de creación cuando el usuario tiene la función `tareas_asignar`
// (sql/014). "Reasignar" sigue existiendo como atajo — las dos entradas
// escriben por sincronizarAsignados(), que es el único escritor de la tabla.
export const editarTareaSchema = tareaEditableSchema
  .extend({
    id: z.string().uuid(),
    responsable_id: z.string().uuid(),
    asignados: z.array(z.string().uuid()).min(1, "Debe haber al menos un asignado"),
  })
  .refine(recurrenciaCompleta, {
    message: "Cantidad y unidad de recurrencia van juntas",
    path: ["recurrencia_unidad"],
  })
  .refine((d) => d.asignados.includes(d.responsable_id), {
    message: "El responsable debe estar entre los asignados",
    path: ["responsable_id"],
  });

export type EditarTareaForm = z.input<typeof editarTareaSchema>;

// Mover un hilo de proyecto no está permitido: la membresía de sus tareas se
// hereda del proyecto y ningún trigger la revalida sobre tareas_hilos (sql/009
// valida UPDATE OF proyecto_id sobre `tareas`, no sobre el hilo). La
// visibilidad sí se edita — no toca la membresía, solo quién ve el hilo.
const hiloEditableSchema = z.object({
  titulo: z.string().min(1, "El título es obligatorio").max(200),
  descripcion: z.string().max(2000).optional(),
});

export const crearHiloSchema = hiloEditableSchema.extend({
  proyecto_id: uuidOpcional,
  visibilidad: z.enum(["publico", "privado"]).default("privado"),
  responsable_id: z.string().uuid(),
});

export type CrearHiloForm = z.input<typeof crearHiloSchema>;

// `visibilidad` acá va sin `.default()` a propósito: en un update, omitirla
// dejaría el hilo en 'privado' sin que nadie lo haya pedido.
export const editarHiloSchema = hiloEditableSchema.extend({
  id: z.string().uuid(),
  visibilidad: z.enum(["publico", "privado"]),
});

export type EditarHiloForm = z.input<typeof editarHiloSchema>;

// Miembros obligatorios en todo proyecto (público o privado): la membresía
// define quién puede recibir tareas del proyecto, no quién lo ve.
export const crearProyectoSchema = z.object({
  nombre: z.string().min(1, "El nombre es obligatorio").max(200),
  descripcion: z.string().max(2000).optional(),
  visibilidad: z.enum(["publico", "privado"]).default("privado"),
  miembros: z.array(z.string().uuid()).min(1, "El proyecto necesita al menos un miembro"),
});

export type CrearProyectoForm = z.input<typeof crearProyectoSchema>;

export const editarProyectoSchema = crearProyectoSchema.extend({ id: z.string().uuid() });

export type EditarProyectoForm = z.input<typeof editarProyectoSchema>;

// `id` presente = paso que ya existe (se actualiza); ausente = paso nuevo.
// crearPlantilla lo ignora — mismo schema para crear y editar.
const plantillaItemSchema = z.object({
  id: z.string().uuid().optional(),
  titulo: z.string().min(1, "El paso no puede estar vacío"),
  orden: z.number().int().default(0),
});

export const crearPlantillaSchema = z.object({
  nombre: z.string().min(1, "El nombre es obligatorio").max(200),
  descripcion: z.string().max(2000).optional(),
  items: z.array(plantillaItemSchema).min(1, "Agregá al menos un paso"),
});

export type CrearPlantillaForm = z.input<typeof crearPlantillaSchema>;

export const editarPlantillaSchema = crearPlantillaSchema.extend({ id: z.string().uuid() });

export type EditarPlantillaForm = z.input<typeof editarPlantillaSchema>;

export const reasignarTareaSchema = z
  .object({
    tarea_id: z.string().uuid(),
    asignados: z.array(z.string().uuid()).min(1, "Debe haber al menos un asignado"),
    responsable_id: z.string().uuid(),
  })
  .refine((d) => d.asignados.includes(d.responsable_id), {
    message: "El responsable debe estar entre los asignados",
    path: ["responsable_id"],
  });

export type ReasignarTareaForm = z.infer<typeof reasignarTareaSchema>;

export const posponerSchema = z.object({
  id: z.string().uuid(),
  hasta: z.string().min(1, "Elegí una fecha"),
});

export type PosponerForm = z.infer<typeof posponerSchema>;

export const completarTareaSchema = z.object({
  tarea_id: z.string().uuid(),
  nota_siguiente: z.string().max(2000).optional(),
});

export type CompletarTareaForm = z.infer<typeof completarTareaSchema>;

export const cerrarHiloSchema = z.object({
  hilo_id: z.string().uuid(),
});

export type CerrarHiloForm = z.infer<typeof cerrarHiloSchema>;

export const agregarDesdePlantillaSchema = z
  .object({
    plantilla_id: z.string().uuid("Elegí una plantilla"),
    hilo_id: z.string().uuid(),
    responsable_id: z.string().uuid(),
    asignados: z.array(z.string().uuid()).min(1, "Debe haber al menos un asignado"),
  })
  .refine((d) => d.asignados.includes(d.responsable_id), {
    message: "El responsable debe estar entre los asignados",
    path: ["responsable_id"],
  });

export type AgregarDesdePlantillaForm = z.infer<typeof agregarDesdePlantillaSchema>;

export const deshacerConversionSchema = z.object({
  hilo_id: z.string().uuid(),
});

export type DeshacerConversionForm = z.infer<typeof deshacerConversionSchema>;

export const agregarNotaTareaSchema = z.object({
  tarea_id: z.string().uuid(),
  nota: z.string().min(1, "La nota no puede estar vacía").max(2000),
});

export type AgregarNotaTareaForm = z.infer<typeof agregarNotaTareaSchema>;

export const agregarNotaHiloSchema = z.object({
  hilo_id: z.string().uuid(),
  nota: z.string().min(1, "La nota no puede estar vacía").max(2000),
});

export type AgregarNotaHiloForm = z.infer<typeof agregarNotaHiloSchema>;

export const filtrosTareasSchema = z.object({
  texto: z.string().optional(),
  asignado_id: z.string().uuid().optional(),
});

export type FiltrosTareas = z.infer<typeof filtrosTareasSchema>;

export const marcarTutorialSchema = z.object({
  pasos: z.array(z.string().min(1).max(80)).min(1),
});

export type MarcarTutorialForm = z.infer<typeof marcarTutorialSchema>;

// Actions de un solo gesto sobre un registro (desactivar, asociar, cambiar
// estado): no tienen formulario, pero la regla de validar en servidor no
// distingue — un id mal formado corta acá y no llega a la base.
export const uuidSchema = z.string().uuid("Identificador inválido");

export const cambiarEstadoTareaSchema = z.object({
  tarea_id: uuidSchema,
  estado: z.enum(["pendiente", "en_progreso", "cancelada"]),
});

export const asociarTareaHiloSchema = z.object({
  tarea_id: uuidSchema,
  hilo_id: uuidSchema,
});

export const temperaturaSchema = z.object({
  tarea_id: uuidSchema,
  temperatura: z
    .number()
    .refine((v) => Number.isInteger(v) && v >= 1 && v <= 100, "Temperatura fuera de rango"),
});
