import { z } from "zod";

export const crearTareaSchema = z.object({
  titulo: z.string().min(1, "El título es obligatorio"),
  descripcion: z.string().optional(),
  hilo_id: z.string().uuid().optional(),
  asignado_a: z.string().uuid("Elegí un usuario asignado"),
  fecha_vencimiento: z.string().optional(),
});

export type CrearTareaForm = z.infer<typeof crearTareaSchema>;

export const crearHiloSchema = z.object({
  titulo: z.string().min(1, "El título es obligatorio"),
});

export type CrearHiloForm = z.infer<typeof crearHiloSchema>;

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
};

export type TareaConRelaciones = Tarea & {
  asignado_a_nombre: string;
  creado_por_nombre: string;
  hilo_titulo: string | null;
};

export type TareaHilo = {
  id: string;
  titulo: string;
  estado: EstadoHilo;
  creado_por: string;
  activo: boolean;
  created_at: string;
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
