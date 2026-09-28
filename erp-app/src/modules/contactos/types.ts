import { z } from "zod";
import type { Database } from "@/lib/supabase/database.types";
import {
  emailOpcional,
  fechaOpcional,
  idSchema,
  telefonoOpcional,
  textoOpcional,
  uuidOpcional,
} from "@/lib/validacion";

type Tablas = Database["public"]["Tables"];
type Funciones = Database["public"]["Functions"];

// Teléfono y email de una persona están fuera del GRANT SELECT: se leen con
// "Ver contacto" (`contactos_ver_contacto`), que deja registro.
export const COLUMNAS_PERSONA = "id, nombre, notas, responsable_id, creado_por, activo, created_at, updated_at";
export type Persona = Omit<Tablas["contactos_personas"]["Row"], "telefono" | "email">;
export type Empresa = Tablas["contactos_empresas"]["Row"];
export type PersonaEmpresa = Tablas["contactos_persona_empresa"]["Row"];
export type Vinculo = Tablas["contactos_vinculos"]["Row"];
export type Edicion = Tablas["contactos_ediciones"]["Row"];
export type DatosContacto = Funciones["contactos_ver_contacto"]["Returns"][number];
export type EdicionContacto = Funciones["contactos_historial_contacto"]["Returns"][number];
export type Vinculable = Funciones["contactos_vinculables"]["Returns"][number];

const nombre = z.string().trim().min(1, "El nombre es obligatorio").max(200, "Máximo 200 caracteres");
const roles = z.array(z.string().min(1)).min(1, "Elegí al menos un rol");

export const personaSchema = z.object({
  nombre,
  telefono: telefonoOpcional,
  email: emailOpcional,
  notas: textoOpcional(5000),
});
export type PersonaForm = z.input<typeof personaSchema>;

// Sin `contacto`, teléfono y email no se tocan: quien edita no los leyó.
export const editarPersonaSchema = z.object({
  id: idSchema,
  nombre,
  notas: textoOpcional(5000),
  contacto: z.object({ telefono: telefonoOpcional, email: emailOpcional }).optional(),
});
export type EditarPersonaForm = z.input<typeof editarPersonaSchema>;

export const empresaSchema = z.object({
  id: idSchema.optional(),
  nombre,
  telefono: telefonoOpcional,
  email: emailOpcional,
  web: textoOpcional(300),
  notas: textoOpcional(5000),
});
export type EmpresaForm = z.input<typeof empresaSchema>;

export const equipoEmpresaSchema = z.object({ id: idSchema, equipo_id: idSchema });
export type EquipoEmpresaForm = z.input<typeof equipoEmpresaSchema>;

export const transferirPersonaSchema = z.object({ id: idSchema, responsable_id: idSchema });
export type TransferirPersonaForm = z.input<typeof transferirPersonaSchema>;

export const personaEmpresaSchema = z.object({
  persona_id: idSchema,
  empresa_id: idSchema,
  cargo: textoOpcional(200),
  desde: fechaOpcional,
});
export type PersonaEmpresaForm = z.input<typeof personaEmpresaSchema>;

export const cerrarSchema = z.object({ id: idSchema, hasta: z.iso.date("Fecha inválida") });
export type CerrarForm = z.input<typeof cerrarSchema>;

// Los roles válidos los declara el ente (`entes.roles`); la base los valida (CO014).
export const vincularSchema = z
  .object({
    ente: z.string().min(1),
    registro_id: idSchema,
    roles,
    persona_id: uuidOpcional,
    empresa_id: uuidOpcional,
  })
  .refine((v) => (v.persona_id === null) !== (v.empresa_id === null), {
    message: "Elegí una persona o una empresa",
    path: ["persona_id"],
  });
export type VincularForm = z.input<typeof vincularSchema>;

export const crearYVincularSchema = z
  .object({
    ente: z.string().min(1),
    registro_id: idSchema,
    roles,
    tipo: z.enum(["persona", "empresa"]),
    nombre,
    telefono: telefonoOpcional,
    email: emailOpcional,
    empresa_id: uuidOpcional,
    empresa_nombre: textoOpcional(200),
    cargo: textoOpcional(200),
  })
  .refine((v) => v.tipo === "persona" || (v.empresa_id === null && v.empresa_nombre === null && v.cargo === null), {
    message: "Una empresa no lleva empresa ni cargo",
    path: ["empresa_id"],
  })
  .refine((v) => v.empresa_id === null || v.empresa_nombre === null, {
    message: "La empresa se elige o se crea, no las dos",
    path: ["empresa_id"],
  });
export type CrearYVincularForm = z.input<typeof crearYVincularSchema>;

export const rolesSchema = z.object({ id: idSchema, roles });
export type RolesForm = z.input<typeof rolesSchema>;

export const buscarSchema = z.string().trim().min(2, "Escribí al menos 2 letras").max(200);
