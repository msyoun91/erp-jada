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
};
