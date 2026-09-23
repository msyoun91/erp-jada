import { z } from "zod";

export const crearUsuarioSchema = z.object({
  nombre: z.string().min(1, "El nombre es obligatorio"),
  email: z.string().min(1, "El email es obligatorio").email("Email inválido"),
  password: z.string().min(8, "La contraseña debe tener al menos 8 caracteres"),
});

export type CrearUsuarioForm = z.infer<typeof crearUsuarioSchema>;

export const editarUsuarioSchema = z.object({
  id: z.string().uuid(),
  nombre: z.string().min(1, "El nombre es obligatorio"),
  email: z.string().min(1, "El email es obligatorio").email("Email inválido"),
});

export type EditarUsuarioForm = z.infer<typeof editarUsuarioSchema>;

export const resetearPasswordSchema = z.object({
  id: z.string().uuid(),
  password: z.string().min(8, "La contraseña debe tener al menos 8 caracteres"),
});

export type ResetearPasswordForm = z.infer<typeof resetearPasswordSchema>;

export const asignarSubmodulosSchema = z.object({
  usuario_id: z.string().uuid(),
  submodulo_ids: z.array(z.string().uuid()),
});

export type AsignarSubmodulosForm = z.infer<typeof asignarSubmodulosSchema>;

export const equipoSchema = z.object({
  id: z.string().uuid().optional(),
  nombre: z.string().trim().min(1, "El nombre es obligatorio"),
});

export type EquipoForm = z.infer<typeof equipoSchema>;

export const asignarEquipoSchema = z.object({
  usuario_id: z.string().uuid(),
  equipo_id: z.string().uuid().nullable(),
});

export type AsignarEquipoForm = z.infer<typeof asignarEquipoSchema>;

export const quitarDelegadorSchema = z.object({
  saliente_id: z.string().uuid(),
  heredero_id: z.string().uuid().nullable(),
  no_copiar: z.array(z.string().uuid()),
});

export type QuitarDelegadorForm = z.infer<typeof quitarDelegadorSchema>;

export const fijarDelegablesSchema = z.object({
  submodulo_ids: z.array(z.string().uuid()),
});

export type FijarDelegablesForm = z.infer<typeof fijarDelegablesSchema>;

export type Equipo = {
  id: string;
  nombre: string;
  activo: boolean;
};

export type Usuario = {
  id: string;
  nombre: string;
  email: string;
  activo: boolean;
  created_at: string;
};

export type Submodulo = {
  id: string;
  codigo: string;
  modulo: string;
  tipo: "vista" | "funcion";
  vista_id: string | null;
  nombre: string;
  orden: number;
  delegable: boolean;
};

export type SubmoduloRegla = {
  submodulo_id: string;
  otro_id: string;
  tipo: "requiere" | "excluye";
};

export type Miembro = Pick<Usuario, "id" | "nombre" | "email" | "activo"> & {
  telefono: string | null;
};

// `otorgada_por` null es del admin, de antes de `sql/104`.
export type Otorgamiento = { submodulo_id: string; otorgada_por: string | null };

export type MiEquipo = {
  yo: string;
  equipo: Equipo;
  miembros: Miembro[];
  permisos: Record<string, Otorgamiento[]>;
};
