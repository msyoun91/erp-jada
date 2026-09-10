import { z } from "zod";
import type { Enums, Tables } from "@/lib/supabase/database.types";

export type Obra = Tables<"obras">;
export type Empresa = Tables<"obras_empresas">;
export type Persona = Tables<"obras_personas">;
export type PersonaEmpresa = Tables<"obras_persona_empresa">;
export type ObraEmpresa = Tables<"obras_obra_empresa">;
export type ObraPersona = Tables<"obras_obra_persona">;
export type ObraReferente = Tables<"obras_obra_referente">;
export type ObraTransferencia = Tables<"obras_transferencias">;
export type Aprobacion = Tables<"obras_aprobaciones">;

export type EstadoObra = Enums<"estado_obra">;
export type TipoObra = Enums<"tipo_obra">;
export type OrigenObra = Enums<"origen_obra">;
export type MotivoPerdida = Enums<"motivo_perdida">;
export type RolEmpresa = Enums<"rol_empresa">;
export type RolPersona = Enums<"rol_persona">;
export type Provincia = Enums<"provincia">;

export type Usuario = { id: string; nombre: string };

export const ESTADOS_OBRA: EstadoObra[] = [
  "idea",
  "en_cotizacion",
  "en_ejecucion",
  "en_postventa",
  "perdida",
  "terminada",
];

export const TIPOS_OBRA: TipoObra[] = [
  "edificio",
  "casa",
  "refaccion",
  "complejo_viviendas",
  "local",
  "oficina",
  "hotel",
  "otro",
];

export const ORIGENES_OBRA: OrigenObra[] = [
  "arquitecto",
  "inmobiliaria",
  "constructora",
  "desarrolladora",
  "referido",
  "deteccion_propia",
  "internet",
  "otro",
];

export const MOTIVOS_PERDIDA: MotivoPerdida[] = [
  "perdimos_licitacion",
  "eligieron_otro_proveedor",
  "precio",
  "especificacion_fuera_de_provision",
  "obra_cancelada",
  "sin_interes",
  "otro",
];

export const ROLES_EMPRESA: RolEmpresa[] = [
  "constructora",
  "desarrolladora",
  "inmobiliaria",
  "estudio_arquitectura",
  "direccion_obra",
  "otro",
];

// Sin "referente": eso es una fila en obras_obra_referente, no un rol.
export const ROLES_PERSONA: RolPersona[] = [
  "arquitecto",
  "desarrollador",
  "inversor",
  "director_obra",
  "compras",
  "oficina_tecnica",
  "decisor",
  "influenciador",
  "contacto_comercial",
  "otro",
];

export const PROVINCIAS: Provincia[] = [
  "caba",
  "buenos_aires",
  "catamarca",
  "chaco",
  "chubut",
  "cordoba",
  "corrientes",
  "entre_rios",
  "formosa",
  "jujuy",
  "la_pampa",
  "la_rioja",
  "mendoza",
  "misiones",
  "neuquen",
  "rio_negro",
  "salta",
  "san_juan",
  "san_luis",
  "santa_cruz",
  "santa_fe",
  "santiago_del_estero",
  "tierra_del_fuego",
  "tucuman",
];

// Los enums viajan en snake_case a la base; la UI nunca los muestra crudos.
export const LABEL_ESTADO: Record<EstadoObra, string> = {
  idea: "Idea",
  en_cotizacion: "En cotización",
  en_ejecucion: "En ejecución",
  en_postventa: "En post-venta",
  perdida: "Perdida",
  terminada: "Terminada",
};

// El estado es dato codificado por color: vive al lado de su label para que el
// listado y la ficha no elijan cada uno el suyo.
export const BADGE_ESTADO: Record<EstadoObra, string> = {
  idea: "badge-neutral",
  en_cotizacion: "badge-warning",
  en_ejecucion: "badge-info",
  en_postventa: "badge-brand",
  perdida: "badge-error",
  terminada: "badge-success",
};

export const LABEL_TIPO: Record<TipoObra, string> = {
  edificio: "Edificio",
  casa: "Casa",
  refaccion: "Refacción",
  complejo_viviendas: "Complejo de viviendas",
  local: "Local",
  oficina: "Oficina",
  hotel: "Hotel",
  otro: "Otro",
};

export const LABEL_ORIGEN: Record<OrigenObra, string> = {
  arquitecto: "Arquitecto",
  inmobiliaria: "Inmobiliaria",
  constructora: "Constructora",
  desarrolladora: "Desarrolladora",
  referido: "Referido",
  deteccion_propia: "Detección propia",
  internet: "Internet",
  otro: "Otro",
};

export const LABEL_MOTIVO_PERDIDA: Record<MotivoPerdida, string> = {
  perdimos_licitacion: "Perdimos la licitación",
  eligieron_otro_proveedor: "Eligieron otro proveedor",
  precio: "Precio",
  especificacion_fuera_de_provision: "Especificación fuera de provisión",
  obra_cancelada: "Obra cancelada",
  sin_interes: "Sin interés",
  otro: "Otro",
};

export const LABEL_ROL_EMPRESA: Record<RolEmpresa, string> = {
  constructora: "Constructora",
  desarrolladora: "Desarrolladora",
  inmobiliaria: "Inmobiliaria",
  estudio_arquitectura: "Estudio de arquitectura",
  direccion_obra: "Dirección de obra",
  otro: "Otro",
};

export const LABEL_ROL_PERSONA: Record<RolPersona, string> = {
  arquitecto: "Arquitecto",
  desarrollador: "Desarrollador",
  inversor: "Inversor",
  director_obra: "Director de obra",
  compras: "Compras",
  oficina_tecnica: "Oficina técnica",
  decisor: "Decisor",
  influenciador: "Influenciador",
  contacto_comercial: "Contacto comercial",
  otro: "Otro",
};

export const LABEL_PROVINCIA: Record<Provincia, string> = {
  caba: "CABA",
  buenos_aires: "Buenos Aires",
  catamarca: "Catamarca",
  chaco: "Chaco",
  chubut: "Chubut",
  cordoba: "Córdoba",
  corrientes: "Corrientes",
  entre_rios: "Entre Ríos",
  formosa: "Formosa",
  jujuy: "Jujuy",
  la_pampa: "La Pampa",
  la_rioja: "La Rioja",
  mendoza: "Mendoza",
  misiones: "Misiones",
  neuquen: "Neuquén",
  rio_negro: "Río Negro",
  salta: "Salta",
  san_juan: "San Juan",
  san_luis: "San Luis",
  santa_cruz: "Santa Cruz",
  santa_fe: "Santa Fe",
  santiago_del_estero: "Santiago del Estero",
  tierra_del_fuego: "Tierra del Fuego",
  tucuman: "Tucumán",
};

// Un <select> con opción vacía manda "" — normaliza a null antes de validar,
// para no mandarle "" a una columna enum o uuid.
const opcionalDeSelect = <T extends z.ZodTypeAny>(schema: T) =>
  z
    .union([schema, z.literal(""), z.null(), z.undefined()])
    .transform((v) => (v === "" || v === undefined ? null : v));

const textoOpcional = (max: number) =>
  z
    .string()
    .max(max)
    .nullish()
    .transform((v) => v?.trim() || null);

const obraEditableSchema = z.object({
  nombre: z.string().trim().min(1, "El nombre es obligatorio").max(200),
  tipo: z.enum(TIPOS_OBRA as [TipoObra, ...TipoObra[]]),
  estado: z.enum(ESTADOS_OBRA as [EstadoObra, ...EstadoObra[]]).default("idea"),
  direccion: textoOpcional(200),
  localidad: textoOpcional(120),
  provincia: opcionalDeSelect(z.enum(PROVINCIAS as [Provincia, ...Provincia[]])),
  origen: opcionalDeSelect(z.enum(ORIGENES_OBRA as [OrigenObra, ...OrigenObra[]])),
  observaciones: textoOpcional(2000),
  motivo_perdida: opcionalDeSelect(
    z.enum(MOTIVOS_PERDIDA as [MotivoPerdida, ...MotivoPerdida[]]),
  ),
  detalle_perdida: textoOpcional(1000),
});

// Espeja los dos CHECK de la tabla. La duplicación es deliberada: el CHECK es
// la barrera real y esto es lo que evita el viaje al servidor para descubrirlo.
const perdidaConMotivo = (d: { estado: EstadoObra; motivo_perdida: MotivoPerdida | null }) =>
  d.estado !== "perdida" || d.motivo_perdida !== null;

const motivoOtroConDetalle = (d: {
  motivo_perdida: MotivoPerdida | null;
  detalle_perdida: string | null;
}) => d.motivo_perdida !== "otro" || !!d.detalle_perdida;

export const crearObraSchema = obraEditableSchema
  .refine(perdidaConMotivo, {
    message: "Una obra perdida necesita un motivo",
    path: ["motivo_perdida"],
  })
  .refine(motivoOtroConDetalle, {
    message: "El motivo 'Otro' necesita un detalle",
    path: ["detalle_perdida"],
  });

export type CrearObraForm = z.input<typeof crearObraSchema>;

export const editarObraSchema = obraEditableSchema
  .extend({ id: z.string().uuid() })
  .refine(perdidaConMotivo, {
    message: "Una obra perdida necesita un motivo",
    path: ["motivo_perdida"],
  })
  .refine(motivoOtroConDetalle, {
    message: "El motivo 'Otro' necesita un detalle",
    path: ["detalle_perdida"],
  });

export type EditarObraForm = z.input<typeof editarObraSchema>;

const empresaEditableSchema = z.object({
  razon_social: z.string().trim().min(1, "La razón social es obligatoria").max(200),
  nombre_comercial: textoOpcional(200),
  website: textoOpcional(200),
  telefono: textoOpcional(50),
  email: z
    .union([z.string().email("Email inválido"), z.literal(""), z.null(), z.undefined()])
    .transform((v) => v || null),
  direccion: textoOpcional(200),
  localidad: textoOpcional(120),
  provincia: opcionalDeSelect(z.enum(PROVINCIAS as [Provincia, ...Provincia[]])),
  observaciones: textoOpcional(2000),
});

export const crearEmpresaSchema = empresaEditableSchema;
export type CrearEmpresaForm = z.input<typeof crearEmpresaSchema>;

export const editarEmpresaSchema = empresaEditableSchema.extend({ id: z.string().uuid() });
export type EditarEmpresaForm = z.input<typeof editarEmpresaSchema>;

const personaEditableSchema = z.object({
  nombre: z.string().trim().min(1, "El nombre es obligatorio").max(100),
  apellido: textoOpcional(100),
  telefono: textoOpcional(50),
  whatsapp: textoOpcional(50),
  email: z
    .union([z.string().email("Email inválido"), z.literal(""), z.null(), z.undefined()])
    .transform((v) => v || null),
  observaciones: textoOpcional(2000),
});

export const crearPersonaSchema = personaEditableSchema;
export type CrearPersonaForm = z.input<typeof crearPersonaSchema>;

export const editarPersonaSchema = personaEditableSchema.extend({ id: z.string().uuid() });
export type EditarPersonaForm = z.input<typeof editarPersonaSchema>;

const rolesEmpresaSchema = z
  .array(z.enum(ROLES_EMPRESA as [RolEmpresa, ...RolEmpresa[]]))
  .min(1, "Elegí al menos un rol")
  .refine((r) => new Set(r).size === r.length, "Hay roles repetidos");

const rolesPersonaSchema = z
  .array(z.enum(ROLES_PERSONA as [RolPersona, ...RolPersona[]]))
  .min(1, "Elegí al menos un rol")
  .refine((r) => new Set(r).size === r.length, "Hay roles repetidos");

// La gente de la empresa entra con la empresa, y cada una con su propio rol:
// compras y arquitecto no son lo mismo aunque trabajen en la misma
// constructora. Vacío es válido — vincular la empresa sola sigue siendo lo
// más común.
export const personaDelLoteSchema = z.object({
  persona_id: z.string().uuid(),
  roles: rolesPersonaSchema,
});

export const vincularEmpresaSchema = z.object({
  obra_id: z.string().uuid(),
  empresa_id: z.string().uuid(),
  roles: rolesEmpresaSchema,
  observaciones: textoOpcional(500),
  personas: z.array(personaDelLoteSchema).default([]),
});

export type VincularEmpresaForm = z.input<typeof vincularEmpresaSchema>;

export const vincularPersonaSchema = z.object({
  obra_id: z.string().uuid(),
  persona_id: z.string().uuid(),
  // A qué empresa representa en esta obra. Es contexto, no invariante: no se
  // valida contra los vínculos de la persona ni contra los de la obra.
  empresa_id: opcionalDeSelect(z.string().uuid()),
  roles: rolesPersonaSchema,
  observaciones: textoOpcional(500),
});

export type VincularPersonaForm = z.input<typeof vincularPersonaSchema>;

export const vincularPersonaEmpresaSchema = z.object({
  persona_id: z.string().uuid(),
  empresa_id: z.string().uuid(),
  cargo: textoOpcional(120),
  es_principal: z.boolean().default(false),
  observaciones: textoOpcional(500),
});

export type VincularPersonaEmpresaForm = z.input<typeof vincularPersonaEmpresaSchema>;

// Máximo 2 decimales: numeric(5,2) en la base redondearía en silencio.
export const referenteSchema = z.object({
  obra_id: z.string().uuid(),
  persona_id: z.string().uuid(),
  porcentaje_comision: z.coerce
    .number()
    .min(0, "La comisión no puede ser negativa")
    .max(100, "La comisión no puede superar 100%")
    .refine((n) => Math.abs(n * 100 - Math.round(n * 100)) < 1e-9, {
      message: "Máximo dos decimales",
    }),
  observaciones: textoOpcional(500),
});

export type ReferenteForm = z.input<typeof referenteSchema>;

export const transferirObraSchema = z.object({
  obra_id: z.string().uuid(),
  a_usuario_id: z.string().uuid(),
  // Contactos vinculados SOLO a esta obra que el checklist de confirmación
  // tildó para mover de dueño con ella. El resto queda como grant contextual.
  contactos_exclusivos: z.array(z.string().uuid()).default([]),
});

export type TransferirObraForm = z.input<typeof transferirObraSchema>;

// Transferir personas y empresas es su propia función (gate obras_personas_todas
// / obras_empresas_todas). La empresa arrastra a su gente exclusiva tildada.
export const transferirPersonaSchema = z.object({
  persona_id: z.string().uuid(),
  a_usuario_id: z.string().uuid(),
});

export type TransferirPersonaForm = z.input<typeof transferirPersonaSchema>;

export const transferirEmpresaSchema = z.object({
  empresa_id: z.string().uuid(),
  a_usuario_id: z.string().uuid(),
  personas_exclusivas: z.array(z.string().uuid()).default([]),
});

export type TransferirEmpresaForm = z.input<typeof transferirEmpresaSchema>;

// Compartir con otro usuario. Lo inicia el dueño; la verificación real está en
// obras_compartir_*. Persona va sola; obra y empresa arrastran las relaciones
// mías que se tilden en el checklist.
export const compartirSchema = z.object({
  id: z.string().uuid(),
  usuario_id: z.string().uuid(),
});

export type CompartirForm = z.input<typeof compartirSchema>;

export const compartirObraSchema = compartirSchema.extend({
  empresas: z.array(z.string().uuid()).default([]),
  personas: z.array(z.string().uuid()).default([]),
});

export type CompartirObraForm = z.input<typeof compartirObraSchema>;

export const compartirEmpresaSchema = compartirSchema.extend({
  personas: z.array(z.string().uuid()).default([]),
});

export type CompartirEmpresaForm = z.input<typeof compartirEmpresaSchema>;

// Lo que devuelve `obras_contactos_exclusivos_de_*`: identidad mínima de lo
// vinculado solo a esa obra/empresa, para el checklist de confirmación.
export type ContactoExclusivo = {
  tipo: "persona" | "empresa";
  id: string;
  etiqueta: string;
  detalle: string | null;
};

// `obras_relaciones_compartibles_*`: identidad mínima de lo vinculado que es
// mío, para el checklist al compartir. `ya_compartida` viene tildada.
export type RelacionCompartible = {
  tipo: "persona" | "empresa";
  id: string;
  etiqueta: string;
  detalle: string | null;
  ya_compartida: boolean;
};

// Con quién está compartida una ficha (persona o empresa).
export type Compartido = {
  usuario_id: string;
  usuario: string;
  created_at: string;
};

// Una fila de la vista Compartido: qué compartí, con quién y de qué origen.
export type CompartidoRow = {
  tipo: "obra" | "empresa" | "persona";
  entidad_id: string;
  entidad_nombre: string;
  usuario_id: string;
  usuario_nombre: string;
  origen: string;
  compartida_el: string;
};

// Alcance del listado. Solo surte efecto para quien tiene el permiso `_todas`
// (o `obras_transferir` en obras): el resto siempre ve lo propio.
export const ALCANCES = ["propios", "todos"] as const;
export type Alcance = (typeof ALCANCES)[number];

export const filtrosObrasSchema = z.object({
  nombre: z.string().optional(),
  estado: opcionalDeSelect(z.enum(ESTADOS_OBRA as [EstadoObra, ...EstadoObra[]])),
  tipo: opcionalDeSelect(z.enum(TIPOS_OBRA as [TipoObra, ...TipoObra[]])),
  localidad: z.string().optional(),
  empresa_id: opcionalDeSelect(z.string().uuid()),
  persona_id: opcionalDeSelect(z.string().uuid()),
  // Solo tiene sentido para quien tiene obras_transferir: es la vista que
  // encuentra las obras de un vendedor dado de baja para reasignarlas.
  responsable_inactivo: z.boolean().optional(),
  // Default 'propios'. 'todos' solo lo respeta el server si el usuario tiene el
  // permiso de ver todo; si no, se ignora.
  alcance: z.enum(ALCANCES).optional(),
});

// Partial: los filtros llegan sueltos desde la URL, nunca todos juntos.
export type FiltrosObras = Partial<z.input<typeof filtrosObrasSchema>>;

// Lo que devuelven las RPC de duplicados. De una entidad ajena llega el nombre
// (obra/razón social) y el del dueño; el resto viene null a propósito, y
// `obra_id`/`empresa_id` también, para que la UI no la enlace.
export type DuplicadoObra = {
  es_mia: boolean;
  obra_id: string | null;
  nombre: string;
  direccion: string | null;
  localidad: string | null;
  responsable: string;
};

export type DuplicadoEmpresa = {
  es_mia: boolean;
  empresa_id: string | null;
  razon_social: string;
  nombre_comercial: string | null;
  localidad: string | null;
  cargada_por: string | null;
};

// Identidad mínima. No trae teléfono ni email — el contacto sale únicamente
// por obras_ficha_persona(), que deja registro.
export type DuplicadoPersona = {
  persona_id: string;
  nombre: string;
  apellido: string | null;
  empresa: string | null;
  coincide: "email" | "telefono" | "nombre";
};

// El buscador global (`sql/037`, enmascarado en `sql/042`). Una fila por
// resultado, mismo tipo para las tres entidades.
//
// `es_ajeno` = true en lo que el usuario no puede abrir: identidad mínima, sin
// contacto ni ficha, `id` en null y `duenio` con el nombre de quien la cargó
// para saber a quién preguntarle. El resto son cosas que ya puede abrir.
export const TIPOS_RESULTADO = ["obra", "empresa", "persona"] as const;

export type TipoResultado = (typeof TIPOS_RESULTADO)[number];

export const LABEL_TIPO_RESULTADO: Record<TipoResultado, string> = {
  obra: "Obras",
  empresa: "Empresas",
  persona: "Personas",
};

export type ResultadoBusqueda = {
  tipo: TipoResultado;
  id: string | null;
  titulo: string;
  subtitulo: string | null;
  es_ajeno: boolean;
  duenio: string | null;
};

// Los dos logs, servidos por función: quien audita ve los accesos y las
// transferencias de todos sin tener permiso sobre la agenda ni sobre las obras
// ajenas. Nunca viaja contacto — la pantalla que vigila el acceso al teléfono
// no puede ser otra puerta al teléfono.
export type AccesoAuditoria = {
  acceso_id: string;
  created_at: string;
  usuario_id: string;
  usuario: string;
  persona_id: string;
  persona: string;
  contexto: string | null;
};

export type TransferenciaAuditoria = {
  transferencia_id: string;
  created_at: string;
  obra_id: string;
  obra: string;
  de_usuario: string;
  a_usuario: string;
  ejecutada_por: string;
};

export type ObraListado = Obra & {
  responsable: Usuario | null;
  empresas: number;
  personas: number;
};

// El listado de personas nunca trae contacto: desde sql/039 esas columnas no
// tienen GRANT SELECT. El contacto sale solo por `getFichaPersona`.
export type PersonaListado = Omit<
  Persona,
  "telefono" | "whatsapp" | "email" | "telefono_norm" | "whatsapp_norm" | "email_norm"
>;

// ── Autorizaciones pendientes (sql/033, recortadas en sql/040) ──────
//
// Solo las tres altas quedan en la cola: el vínculo a entidad ajena ya no se
// congela (bajo model A no se puede vincular lo que no se ve). El `tipo` es una
// lista blanca de nombres de tabla, no un enum de Postgres.

export const TIPOS_PENDIENTE = ["obra", "empresa", "persona"] as const;

export type TipoPendiente = (typeof TIPOS_PENDIENTE)[number];

export const LABEL_TIPO_PENDIENTE: Record<TipoPendiente, string> = {
  obra: "Obra nueva",
  empresa: "Empresa nueva",
  persona: "Persona nueva",
};

export type Pendiente = {
  tipo: TipoPendiente;
  registro_id: string;
  etiqueta: string;
  motivo: string;
  solicitante: string;
  created_at: string;
};

// Contra qué se parece. Solo para quien tiene `obras_aprobar`: es la única
// pantalla del módulo que muestra el nombre de una obra ajena.
export type SimilarPendiente = {
  etiqueta: string;
  detalle: string | null;
};

export type HistorialAprobacion = {
  aprobacion_id: string;
  created_at: string;
  tipo: TipoPendiente;
  etiqueta: string;
  aprobada: boolean;
  motivo: string | null;
  decidido_por: string;
};

// Identidad mínima otra vez: la lista que se tilda al vincular una empresa no
// puede ser una puerta al contacto de su gente.
export type PersonaDeEmpresa = {
  persona_id: string;
  nombre: string;
  apellido: string | null;
  cargo: string | null;
  es_principal: boolean;
  es_mia: boolean;
  ya_en_obra: boolean;
};

export const resolverPendienteSchema = z
  .object({
    tipo: z.enum(TIPOS_PENDIENTE),
    registro_id: z.string().uuid(),
    aprobar: z.boolean(),
    motivo: textoOpcional(500),
  })
  // Espeja el OB016 de la base: el motivo es lo único que va a leer quien la
  // cargó, así que un rechazo sin motivo no es una decisión, es un silencio.
  .refine((d) => d.aprobar || !!d.motivo, {
    message: "El rechazo necesita un motivo",
    path: ["motivo"],
  });

export type ResolverPendienteForm = z.input<typeof resolverPendienteSchema>;
