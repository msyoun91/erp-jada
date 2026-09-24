import { z } from "zod";
import type { Database } from "@/lib/supabase/database.types";

type Enums = Database["public"]["Enums"];
type Tablas = Database["public"]["Tables"];

export type EstadoHilo = Enums["estado_hilo"];
export type EstadoTarea = Enums["estado_tarea"];
export type PrioridadTarea = Enums["prioridad_tarea"];
export type RecurrenciaUnidad = Enums["recurrencia_unidad"];

export type Hilo = Tablas["tareas_hilos"]["Row"];
export type Tarea = Tablas["tareas"]["Row"];
export type Nota = Tablas["tareas_notas"]["Row"];
export type Edicion = Tablas["tareas_ediciones"]["Row"];
export type Plantilla = Tablas["tareas_plantillas"]["Row"];
export type PlantillaPaso = Tablas["tareas_plantillas_pasos"]["Row"];
export type Asignable = Database["public"]["Functions"]["tareas_asignables"]["Returns"][number];

// Un <select> o <input type="date"> vacío manda "", no undefined.
const uuidOpcional = z
  .union([z.string().uuid(), z.literal("")])
  .nullish()
  .transform((v) => v || null);
const fechaOpcional = z
  .union([z.iso.date("Fecha inválida"), z.literal("")])
  .nullish()
  .transform((v) => v || null);
const textoOpcional = (max: number) =>
  z
    .string()
    .trim()
    .max(max, `Máximo ${max} caracteres`)
    .nullish()
    .transform((v) => v || null);
const titulo = z.string().trim().min(1, "El título es obligatorio").max(500, "Máximo 500 caracteres");
const enteros = z.coerce.number().int("Tiene que ser un número entero").positive("Tiene que ser mayor a 0");
const diasOpcional = z
  .union([enteros, z.literal("")])
  .nullish()
  .transform((v) => (v === "" || v == null ? null : v));

export const idSchema = z.string().uuid();

// Exactamente uno: una persona o un equipo.
const asignado = {
  asignado_id: uuidOpcional,
  asignado_equipo_id: uuidOpcional,
};
const unAsignado = (v: { asignado_id: string | null; asignado_equipo_id: string | null }) =>
  (v.asignado_id === null) !== (v.asignado_equipo_id === null);
const mensajeAsignado = { message: "Elegí a quién se asigna", path: ["asignado_id"] };

export const hiloSchema = z
  .object({
    id: idSchema.optional(),
    titulo,
    recurrencia_cantidad: diasOpcional,
    recurrencia_unidad: z.union([z.enum(["dia", "mes"]), z.literal("")]).nullish().transform((v) => v || null),
  })
  .refine((v) => (v.recurrencia_cantidad === null) === (v.recurrencia_unidad === null), {
    message: "La recurrencia lleva cantidad y unidad",
    path: ["recurrencia_cantidad"],
  });
export type HiloForm = z.input<typeof hiloSchema>;

const contenidoPaso = {
  titulo,
  descripcion: textoOpcional(5000),
  prioridad: z.enum(["baja", "media", "alta"]).default("media"),
  vence: fechaOpcional,
  vence_dias: diasOpcional,
};

export const pasoSchema = z
  .object({
    hilo_id: idSchema,
    paso_anterior_id: uuidOpcional,
    ...contenidoPaso,
    ...asignado,
  })
  .refine(unAsignado, mensajeAsignado)
  .refine((v) => v.vence_dias === null || v.paso_anterior_id !== null, {
    message: "El plazo en días va con un paso anterior",
    path: ["vence_dias"],
  })
  .refine((v) => v.vence === null || v.vence_dias === null, {
    message: "Una fecha o un plazo en días, no los dos",
    path: ["vence"],
  });
export type PasoForm = z.input<typeof pasoSchema>;

export const insertarAntesSchema = z
  .object({
    siguiente_id: idSchema,
    ...contenidoPaso,
    ...asignado,
  })
  .refine(unAsignado, mensajeAsignado)
  .refine((v) => v.vence === null || v.vence_dias === null, {
    message: "Una fecha o un plazo en días, no los dos",
    path: ["vence"],
  });
export type InsertarAntesForm = z.input<typeof insertarAntesSchema>;

// Con plazo en días la base calcula `vence`: se manda uno u otro.
export const editarPasoSchema = z
  .object({ id: idSchema, ...contenidoPaso })
  .refine((v) => v.vence === null || v.vence_dias === null, {
    message: "Una fecha o un plazo en días, no los dos",
    path: ["vence"],
  });
export type EditarPasoForm = z.input<typeof editarPasoSchema>;

export const reasignarSchema = z.object({ id: idSchema, ...asignado }).refine(unAsignado, mensajeAsignado);
export type ReasignarForm = z.input<typeof reasignarSchema>;

export const rechazarSchema = z.object({
  id: idSchema,
  motivo_rechazo: z.string().trim().min(1, "El motivo es obligatorio").max(2000, "Máximo 2000 caracteres"),
});
export type RechazarForm = z.input<typeof rechazarSchema>;

export const completarSchema = z.object({ id: idSchema, resultado: textoOpcional(5000) });
export type CompletarForm = z.input<typeof completarSchema>;

export const completarAjenoSchema = z.object({
  id: idSchema,
  nota: z.string().trim().min(1, "La nota es obligatoria").max(5000, "Máximo 5000 caracteres"),
  resultado: textoOpcional(5000),
});
export type CompletarAjenoForm = z.input<typeof completarAjenoSchema>;

export const esperaSchema = z
  .object({
    id: idSchema,
    espera_hasta: fechaOpcional,
    espera_motivo: textoOpcional(500),
  })
  .refine((v) => v.espera_motivo === null || v.espera_hasta !== null, {
    message: "El motivo va con una fecha",
    path: ["espera_motivo"],
  });
export type EsperaForm = z.input<typeof esperaSchema>;

export const notaSchema = z.object({
  hilo_id: idSchema,
  tarea_id: uuidOpcional,
  texto: z.string().trim().min(1, "La nota está vacía").max(5000, "Máximo 5000 caracteres"),
});
export type NotaForm = z.input<typeof notaSchema>;

export const cerrarHiloSchema = z.object({
  id: idSchema,
  resultado: textoOpcional(5000),
  // Con recurrencia: false = cerrar sin generar el siguiente.
  generar: z.boolean().default(true),
  cancelar_pendientes: z.boolean().default(false),
});
export type CerrarHiloForm = z.input<typeof cerrarHiloSchema>;

export const transferirSchema = z.object({ id: idSchema, responsable_id: idSchema });
export type TransferirForm = z.input<typeof transferirSchema>;

export const plantillaPasoSchema = z
  .object({
    titulo,
    descripcion: textoOpcional(5000),
    ...asignado,
    prioridad: z.enum(["baja", "media", "alta"]).default("media"),
    vence_dias: diasOpcional,
    espera_anterior: z.boolean().default(true),
  })
  .refine((v) => v.asignado_id === null || v.asignado_equipo_id === null, {
    message: "Una persona o un equipo, no los dos",
    path: ["asignado_id"],
  });

export const plantillaSchema = z.object({
  id: idSchema.optional(),
  nombre: z.string().trim().min(1, "El nombre es obligatorio").max(500, "Máximo 500 caracteres"),
  descripcion: textoOpcional(5000),
  pasos: z.array(plantillaPasoSchema).min(1, "La plantilla necesita al menos un paso"),
});
export type PlantillaForm = z.input<typeof plantillaSchema>;

export const usarPlantillaSchema = z.object({
  plantilla_id: idSchema,
  titulo: textoOpcional(500),
  hilo_id: uuidOpcional,
  // paso de la plantilla → a quién, cuando se elige al usarla.
  asignados: z.record(
    idSchema,
    z.object(asignado).refine(unAsignado, mensajeAsignado)
  ),
});
export type UsarPlantillaForm = z.input<typeof usarPlantillaSchema>;
