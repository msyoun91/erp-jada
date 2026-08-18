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
};

export type ProyectoMiembro = { usuario_id: string; usuarios: UsuarioNombre | null };

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

export const crearTareaSchema = z
  .object({
    titulo: z.string().min(1, "El título es obligatorio").max(200),
    descripcion: z.string().max(2000).optional(),
    hilo_id: uuidOpcional,
    proyecto_id: uuidOpcional,
    visibilidad: z.enum(["publico", "privado"]).default("privado"),
    responsable_id: z.string().uuid(),
    asignados: z.array(z.string().uuid()).min(1, "Debe haber al menos un asignado"),
    fecha_vencimiento: fechaOpcional,
    temperatura: z.coerce.number().int().min(1).max(100).default(50),
    recurrencia_cantidad: z.coerce.number().int().positive().nullish(),
    recurrencia_unidad: z.enum(["dia", "mes"]).nullish(),
    modo_completado: z.enum(["manual", "automatico", "hibrido"]).default("manual"),
    origen_app: z.string().max(100).optional(),
    origen_punto: z.string().max(500).optional(),
  })
  .refine((d) => !(d.hilo_id && d.proyecto_id), {
    message: "Una tarea con hilo no lleva proyecto propio — lo hereda del hilo",
    path: ["proyecto_id"],
  })
  .refine((d) => (d.recurrencia_cantidad == null) === (d.recurrencia_unidad == null), {
    message: "Cantidad y unidad de recurrencia van juntas",
    path: ["recurrencia_unidad"],
  })
  .refine((d) => d.asignados.includes(d.responsable_id), {
    message: "El responsable debe estar entre los asignados",
    path: ["responsable_id"],
  });

export type CrearTareaForm = z.input<typeof crearTareaSchema>;
export type CrearTareaValues = z.output<typeof crearTareaSchema>;

export const crearHiloSchema = z.object({
  titulo: z.string().min(1, "El título es obligatorio").max(200),
  descripcion: z.string().max(2000).optional(),
  proyecto_id: uuidOpcional,
  visibilidad: z.enum(["publico", "privado"]).default("privado"),
  responsable_id: z.string().uuid(),
});

export type CrearHiloForm = z.input<typeof crearHiloSchema>;

export const crearProyectoSchema = z
  .object({
    nombre: z.string().min(1, "El nombre es obligatorio").max(200),
    descripcion: z.string().max(2000).optional(),
    visibilidad: z.enum(["publico", "privado"]).default("privado"),
    miembros: z.array(z.string().uuid()).optional(),
  })
  .refine((d) => d.visibilidad === "publico" || (d.miembros?.length ?? 0) > 0, {
    message: "Un proyecto privado necesita al menos un miembro",
    path: ["miembros"],
  });

export type CrearProyectoForm = z.input<typeof crearProyectoSchema>;

export const crearPlantillaSchema = z.object({
  nombre: z.string().min(1, "El nombre es obligatorio").max(200),
  descripcion: z.string().max(2000).optional(),
  items: z
    .array(z.object({ titulo: z.string().min(1, "El paso no puede estar vacío"), orden: z.number().int().default(0) }))
    .min(1, "Agregá al menos un paso"),
});

export type CrearPlantillaForm = z.input<typeof crearPlantillaSchema>;

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

export const agregarPasoSchema = z.object({
  tarea_id: z.string().uuid(),
  titulo_paso: z.string().min(1, "El paso no puede estar vacío").max(200),
});

export type AgregarPasoForm = z.infer<typeof agregarPasoSchema>;

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
