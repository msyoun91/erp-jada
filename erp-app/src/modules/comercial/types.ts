import { z } from "zod";
import type { Enums, Tables } from "@/lib/supabase/database.types";

export type Empresa = Tables<"empresas">;
export type Persona = Tables<"personas">;
export type Obra = Tables<"obras">;
export type ObraEmpresa = Tables<"obra_empresa">;
export type ObraPersona = Tables<"obra_persona">;
export type Prospecto = Tables<"comercial_prospectos">;
export type Fuente = Tables<"comercial_fuentes">;

export type TipoObra = Enums<"tipo_obra">;
export type EstadoObra = Enums<"estado_obra">;
export type EstadoProspecto = Enums<"estado_prospecto">;
export type RolEmpresa = Enums<"rol_empresa">;
export type RolPersona = Enums<"rol_persona">;
export type Moneda = Enums<"moneda">;

export type Usuario = { id: string; nombre: string };

// Un <input> de texto vacío manda "" — las columnas nullable guardan null, no
// "". Normaliza en el schema y no en cada action.
const textoOpcional = z
  .string()
  .nullish()
  .transform((v) => v?.trim() || null);

const fechaOpcional = z
  .string()
  .nullish()
  .transform((v) => v || null);

const uuidOpcional = z
  .union([z.string().uuid(), z.literal(""), z.null(), z.undefined()])
  .transform((v) => v || null);

// El CUIT se guarda como 11 dígitos: es la clave de deduplicación de empresas,
// y "30-71234567-8" y "30712345678" no pueden ser dos empresas distintas.
const cuitOpcional = z
  .string()
  .nullish()
  .transform((v) => (v ? v.replace(/\D/g, "") : null))
  .refine((v) => v === null || v.length === 0 || /^\d{11}$/.test(v), "El CUIT debe tener 11 dígitos")
  .transform((v) => v || null);

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

const emailOpcional = z
  .string()
  .nullish()
  .transform((v) => v?.trim() || null)
  .refine((v) => v === null || EMAIL_RE.test(v), "Email inválido");

const enteroPositivoOpcional = z
  .union([z.number(), z.string(), z.null(), z.undefined()])
  .transform((v) => (v === "" || v === null || v === undefined ? null : Number(v)))
  .refine(
    (v) => v === null || (Number.isInteger(v) && v > 0),
    "Debe ser un número entero mayor a 0"
  );

const decimalPositivoOpcional = z
  .union([z.number(), z.string(), z.null(), z.undefined()])
  .transform((v) => (v === "" || v === null || v === undefined ? null : Number(v)))
  .refine((v) => v === null || (Number.isFinite(v) && v > 0), "Debe ser un número mayor a 0");

// null = sin comisión. 0 = 0% configurado explícitamente. La diferencia la
// guarda la existencia de la fila en comercial_comisiones, no un booleano.
const porcentajeOpcional = z
  .union([z.number(), z.string(), z.null(), z.undefined()])
  .transform((v) => (v === "" || v === null || v === undefined ? null : Number(v)))
  .refine(
    (v) => v === null || (Number.isFinite(v) && v >= 0 && v <= 100),
    "El porcentaje debe estar entre 0 y 100"
  )
  .refine(
    (v) => v === null || Math.round(v * 100) === v * 100,
    "El porcentaje admite hasta 2 decimales"
  );

export const TIPOS_OBRA = [
  "edificio_residencial",
  "edificio_comercial",
  "vivienda",
  "oficinas",
  "local",
  "desarrollo_mixto",
  "otro",
] as const;

export const ESTADOS_OBRA = [
  "idea",
  "proyecto",
  "pozo",
  "inicio_obra",
  "construccion",
  "terminaciones",
  "finalizada",
  "desconocido",
] as const;

export const ESTADOS_PROSPECTO = [
  "nuevo",
  "investigando",
  "contactado",
  "en_seguimiento",
  "interes_confirmado",
  "cotizacion_solicitada",
  "cotizado",
  "negociacion",
  "ganado",
  "perdido",
  "sin_oportunidad",
] as const;

export const ROLES_EMPRESA = [
  "desarrolladora",
  "constructora",
  "inmobiliaria",
  "estudio_arquitectura",
  "inversor",
  "proveedor",
  "otro",
] as const;

export const ROLES_PERSONA = [
  "arquitecto",
  "desarrollador",
  "inversor",
  "director",
  "compras",
  "oficina_tecnica",
  "decisor",
  "influenciador",
  "contacto_comercial",
  "otro",
] as const;

export const MONEDAS = ["ARS", "USD"] as const;

export const empresaSchema = z.object({
  razon_social: z.string().min(1, "La razón social es obligatoria").max(200),
  nombre_comercial: textoOpcional,
  cuit: cuitOpcional,
  website: textoOpcional,
  telefono: textoOpcional,
  email: emailOpcional,
  direccion: textoOpcional,
  localidad: textoOpcional,
  provincia: textoOpcional,
  observaciones: textoOpcional,
});

export const editarEmpresaSchema = empresaSchema.extend({ id: z.string().uuid() });

export const personaSchema = z.object({
  nombre: z.string().min(1, "El nombre es obligatorio").max(100),
  apellido: textoOpcional,
  telefono: textoOpcional,
  whatsapp: textoOpcional,
  email: emailOpcional,
  cargo: textoOpcional,
  empresa_principal_id: uuidOpcional,
  observaciones: textoOpcional,
});

export const editarPersonaSchema = personaSchema.extend({ id: z.string().uuid() });

export const obraSchema = z.object({
  nombre: z.string().min(1, "El nombre es obligatorio").max(200),
  direccion: textoOpcional,
  localidad: textoOpcional,
  provincia: textoOpcional,
  tipo: z.enum(TIPOS_OBRA).default("otro"),
  estado_obra: z.enum(ESTADOS_OBRA).default("desconocido"),
  cantidad_unidades: enteroPositivoOpcional,
  superficie_estimada: decimalPositivoOpcional,
  fecha_estimada_inicio: fechaOpcional,
  observaciones: textoOpcional,
});

export const editarObraSchema = obraSchema.extend({ id: z.string().uuid() });

// El monto sin moneda no se puede leer y la moneda sin monto es ruido — la
// misma regla que el CHECK `potencial_con_moneda`. Se repite acá porque el
// formulario tiene que poder señalar el campo, no mostrar un error de Postgres.
export const prospectoSchema = z
  .object({
    obra_id: z.string().uuid("Elegí una obra"),
    estado_prospecto: z.enum(ESTADOS_PROSPECTO).default("nuevo"),
    fuente_id: uuidOpcional,
    responsable_id: z.string().uuid("Elegí un responsable"),
    potencial_estimado: decimalPositivoOpcional,
    moneda_potencial: z
      .union([z.enum(MONEDAS), z.literal(""), z.null(), z.undefined()])
      .transform((v) => v || null),
    fecha_estimada_compra: fechaOpcional,
    observaciones: textoOpcional,
  })
  .refine((d) => (d.potencial_estimado === null) === (d.moneda_potencial === null), {
    message: "El potencial necesita moneda",
    path: ["moneda_potencial"],
  });

export const editarProspectoSchema = z.intersection(
  prospectoSchema,
  z.object({ id: z.string().uuid() })
);

export const relacionEmpresaSchema = z.object({
  obra_id: z.string().uuid(),
  empresa_id: z.string().uuid("Elegí una empresa"),
  roles: z.array(z.enum(ROLES_EMPRESA)).min(1, "Elegí al menos un rol"),
  observaciones: textoOpcional,
});

export const editarRelacionEmpresaSchema = relacionEmpresaSchema.extend({
  id: z.string().uuid(),
});

export const relacionPersonaSchema = z.object({
  obra_id: z.string().uuid(),
  persona_id: z.string().uuid("Elegí una persona"),
  empresa_id: uuidOpcional,
  roles: z.array(z.enum(ROLES_PERSONA)).min(1, "Elegí al menos un rol"),
  es_referente: z.boolean().default(false),
  porcentaje_comision: porcentajeOpcional,
  observaciones: textoOpcional,
});

export const editarRelacionPersonaSchema = relacionPersonaSchema.extend({
  id: z.string().uuid(),
});

export type EmpresaForm = z.input<typeof empresaSchema>;
export type PersonaForm = z.input<typeof personaSchema>;
export type ObraForm = z.input<typeof obraSchema>;
export type ProspectoForm = z.input<typeof prospectoSchema>;
export type RelacionEmpresaForm = z.input<typeof relacionEmpresaSchema>;
export type RelacionPersonaForm = z.input<typeof relacionPersonaSchema>;

export type EditarEmpresaForm = z.input<typeof editarEmpresaSchema>;
export type EditarPersonaForm = z.input<typeof editarPersonaSchema>;
export type EditarObraForm = z.input<typeof editarObraSchema>;
export type EditarProspectoForm = z.input<typeof editarProspectoSchema>;
export type EditarRelacionEmpresaForm = z.input<typeof editarRelacionEmpresaSchema>;
export type EditarRelacionPersonaForm = z.input<typeof editarRelacionPersonaSchema>;

export type EmpresaConRoles = ObraEmpresa & { empresas: Empresa | null };

// `comision` llega como array porque es una relación embebida de Supabase; es
// 0 o 1 fila (unique parcial). Sin el permiso `comercial_comision` la RLS la
// deja vacía — no hay bandera aparte que decir "hay comisión pero no la ves".
export type PersonaConRoles = ObraPersona & {
  personas: Persona | null;
  empresas: Pick<Empresa, "id" | "razon_social" | "nombre_comercial"> | null;
  comercial_comisiones: { id: string; porcentaje: number; activo: boolean }[];
};

export type PersonaConEmpresa = Persona & {
  empresas: Pick<Empresa, "id" | "razon_social" | "nombre_comercial"> | null;
};

export type ObraConRelaciones = Obra & {
  obra_empresa: EmpresaConRoles[];
  obra_persona: PersonaConRoles[];
};

export type ProspectoListado = Prospecto & {
  obras: ObraConRelaciones | null;
  comercial_fuentes: Pick<Fuente, "id" | "nombre"> | null;
  usuarios: Pick<Usuario, "id" | "nombre"> | null;
};
