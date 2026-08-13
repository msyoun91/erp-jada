import { z } from "zod";
import { hoyISO } from "@/lib/utils";

export const TAREAS_PAGE_SIZE = 20;
export type ModoTareas = "abiertas" | "completadas" | "pospuestas";

export const filtrosTareasSchema = z.object({
  texto: z.string().trim().max(100).optional(),
  asignado_a: z.string().uuid().optional(),
});

export type FiltrosTareas = z.infer<typeof filtrosTareasSchema>;

export const recurrenciaIntervaloEnum = z.enum(["dia", "mes", "anio"]);
export type RecurrenciaIntervalo = z.infer<typeof recurrenciaIntervaloEnum>;

// Un input date vacío manda "", que Postgres rechaza en una columna date.
// `nullish`: el cliente reenvía al server action el valor ya transformado.
const fechaOpcional = z
  .string()
  .nullish()
  .transform((v) => v || null);

const recurrenciaFields = {
  recurrencia_activa: z.boolean().default(false),
  recurrencia_una_vez: z.boolean().default(false),
  recurrencia_intervalo: recurrenciaIntervaloEnum.optional(),
  recurrencia_cada: z.coerce.number().int().min(1).default(1),
  recurrencia_proxima: fechaOpcional,
};

function recurrenciaCompleta(d: { recurrencia_activa: boolean; recurrencia_intervalo?: unknown; recurrencia_proxima?: unknown }) {
  return !d.recurrencia_activa || (Boolean(d.recurrencia_intervalo) && Boolean(d.recurrencia_proxima));
}

// El `min` de los date inputs es solo UI: sin esto, una fecha pasada se guarda
// y queda una recurrencia que el cron nunca dispara.
function recurrenciaFechaFutura(d: { recurrencia_activa: boolean; recurrencia_proxima?: unknown }) {
  if (!d.recurrencia_activa || typeof d.recurrencia_proxima !== "string") return true;
  return d.recurrencia_proxima >= hoyISO();
}

const fechaPasada = {
  message: "La próxima repetición no puede ser una fecha pasada",
  path: ["recurrencia_proxima"],
};

export const crearTareaSchema = z
  .object({
    titulo: z.string().min(1, "El título es obligatorio"),
    descripcion: z.string().optional(),
    hilo_id: z.string().uuid().optional(),
    asignado_a: z.string().uuid("Elegí un usuario asignado"),
    fecha_vencimiento: fechaOpcional,
    ...recurrenciaFields,
  })
  .refine(recurrenciaCompleta, {
    message: "Elegí intervalo y próxima fecha de repetición",
    path: ["recurrencia_proxima"],
  })
  .refine(recurrenciaFechaFutura, fechaPasada);

export type CrearTareaForm = z.input<typeof crearTareaSchema>;
export type CrearTareaValues = z.output<typeof crearTareaSchema>;

export const crearHiloSchema = z
  .object({
    titulo: z.string().min(1, "El título es obligatorio"),
    descripcion: z.string().optional(),
    ...recurrenciaFields,
  })
  .refine(recurrenciaCompleta, {
    message: "Elegí intervalo y próxima fecha de repetición",
    path: ["recurrencia_proxima"],
  })
  .refine(recurrenciaFechaFutura, fechaPasada);

export type CrearHiloForm = z.input<typeof crearHiloSchema>;

export const actualizarRecurrenciaTareaSchema = z
  .object({
    tarea_id: z.string().uuid(),
    ...recurrenciaFields,
  })
  .refine(recurrenciaCompleta, {
    message: "Elegí intervalo y próxima fecha de repetición",
    path: ["recurrencia_proxima"],
  })
  .refine(recurrenciaFechaFutura, fechaPasada);

export type ActualizarRecurrenciaTareaForm = z.input<typeof actualizarRecurrenciaTareaSchema>;

export const posponerTareaSchema = z.object({
  tarea_id: z.string().uuid(),
  posponer_hasta: z.string().min(1, "Elegí una fecha"),
});

export type PosponerTareaForm = z.infer<typeof posponerTareaSchema>;

export const posponerHiloSchema = z.object({
  hilo_id: z.string().uuid(),
  posponer_hasta: z.string().min(1, "Elegí una fecha"),
});

export type PosponerHiloForm = z.infer<typeof posponerHiloSchema>;

export const asociarHiloSchema = z.object({
  tarea_id: z.string().uuid(),
  hilo_id: z.string().uuid(),
});

export type AsociarHiloForm = z.infer<typeof asociarHiloSchema>;

export const agregarNotaSchema = z.object({
  tarea_id: z.string().uuid(),
  nota: z.string().min(1, "La nota es obligatoria"),
});

export type AgregarNotaForm = z.infer<typeof agregarNotaSchema>;

export const reasignarTareaSchema = z.object({
  tarea_id: z.string().uuid(),
  asignado_a: z.string().uuid("Elegí un usuario asignado"),
});

export type ReasignarTareaForm = z.infer<typeof reasignarTareaSchema>;

export const actualizarEstadoSchema = z.object({
  tarea_id: z.string().uuid(),
  estado: z.enum(["pendiente", "en_progreso", "completada"]),
});

export type ActualizarEstadoForm = z.infer<typeof actualizarEstadoSchema>;

const plantillaItemSchema = z.object({
  titulo: z.string().min(1, "El título es obligatorio"),
  descripcion: z.string().optional(),
});

export const crearPlantillaSchema = z.object({
  nombre: z.string().min(1, "El nombre es obligatorio"),
  items: z.array(plantillaItemSchema).min(1, "Agregá al menos una tarea"),
});

export type CrearPlantillaForm = z.infer<typeof crearPlantillaSchema>;

export const agregarDesdePlantillaSchema = z.object({
  hilo_id: z.string().uuid(),
  plantilla_id: z.string().uuid(),
  asignado_a: z.string().uuid("Elegí un usuario asignado"),
});

export type AgregarDesdePlantillaForm = z.infer<typeof agregarDesdePlantillaSchema>;

export type EstadoTarea = "pendiente" | "en_progreso" | "completada";
export type EstadoHilo = "abierto" | "cerrado";

export type Tarea = {
  id: string;
  hilo_id: string | null;
  titulo: string;
  descripcion: string | null;
  asignado_a: string;
  creado_por: string;
  estado: EstadoTarea;
  fecha_vencimiento: string | null;
  activo: boolean;
  created_at: string;
  updated_at: string;
  recurrencia_activa: boolean;
  recurrencia_una_vez: boolean;
  recurrencia_intervalo: RecurrenciaIntervalo | null;
  recurrencia_cada: number;
  recurrencia_proxima: string | null;
  posponer_hasta: string | null;
};

export type TareaConRelaciones = Tarea & {
  asignado_a_nombre: string;
  creado_por_nombre: string;
  hilo_titulo: string | null;
};

export type TareaHilo = {
  id: string;
  titulo: string;
  descripcion: string | null;
  estado: EstadoHilo;
  creado_por: string;
  activo: boolean;
  created_at: string;
  recurrencia_activa: boolean;
  recurrencia_una_vez: boolean;
  recurrencia_intervalo: RecurrenciaIntervalo | null;
  recurrencia_cada: number;
  recurrencia_proxima: string | null;
  posponer_hasta: string | null;
};

export const filtrosAuditoriaSchema = z.object({
  usuario_id: z.string().uuid().optional(),
  desde: z.string().optional(),
  hasta: z.string().optional(),
});

export type FiltrosAuditoria = z.infer<typeof filtrosAuditoriaSchema>;

export type TareaEvento = {
  id: string;
  tarea_id: string;
  tarea_titulo: string;
  hilo_titulo: string | null;
  usuario_nombre: string | null;
  estado_anterior: EstadoTarea | null;
  estado_nuevo: EstadoTarea;
  created_at: string;
};

export type DiaAuditoria = {
  dia: string;
  eventos: TareaEvento[];
};

export type TareaNota = {
  id: string;
  tarea_id: string;
  usuario_id: string;
  usuario_nombre: string;
  nota: string;
  created_at: string;
};

export type TareaPlantillaItem = {
  id: string;
  plantilla_id: string;
  titulo: string;
  descripcion: string | null;
  orden: number;
};

export type TareaPlantilla = {
  id: string;
  nombre: string;
  creado_por: string;
  activo: boolean;
  created_at: string;
  items: TareaPlantillaItem[];
};
