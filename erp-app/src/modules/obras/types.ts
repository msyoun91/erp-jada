import { z } from "zod";
import { ENTES } from "@/lib/entes";
import type { Database } from "@/lib/supabase/database.types";
import { emailOpcional, idSchema, telefonoOpcional, textoOpcional, uuidOpcional } from "@/lib/validacion";

type Enums = Database["public"]["Enums"];
type Tablas = Database["public"]["Tables"];

export type EstadoObra = Enums["estado_obra"];
export type MotivoPerdida = Enums["motivo_perdida"];
export type OrigenObra = Enums["origen_obra"];
export type TipoObra = Enums["tipo_obra"];

export type Obra = Tablas["obras"]["Row"];
export type Participante = Tablas["obras_participantes"]["Row"];

export const LABEL_ESTADO = ENTES.obra.estados;
export const LABEL_ROL = ENTES.obra.roles;

const ESTADOS = ["idea", "en_busqueda", "en_cotizacion", "contratada", "perdida"] as const;
export const ESTADOS_ABIERTOS = ["idea", "en_busqueda", "en_cotizacion"] as const;
const MOTIVOS = ["precio", "plazo", "producto", "proveedor_habitual", "obra_suspendida", "sin_respuesta", "otro"] as const;
const ORIGENES = ["referente", "cartel", "web_redes", "cliente_anterior", "llamado", "otro"] as const;
const TIPOS = ["edificio_residencial", "casa", "oficinas_comercial", "industrial", "otro"] as const;

const texto = (campo: string, max: number) =>
  z.string().trim().min(1, `${campo} es obligatorio`).max(max, `Máximo ${max} caracteres`);

// <input type="month"> manda "2026-11"; la base guarda el día 1 (CHECK).
const mesOpcional = z
  .union([z.string().regex(/^\d{4}-\d{2}$/, "Mes inválido"), z.literal("")])
  .nullish()
  .transform((v) => (v ? `${v}-01` : null));

const datos = {
  nombre: texto("El nombre", 200),
  direccion: texto("La dirección", 300),
  localidad: textoOpcional(120),
  notas: textoOpcional(5000),
  origen: z.enum(ORIGENES, "Elegí el origen"),
  tipo: z.enum(TIPOS, "Elegí el tipo de obra"),
  compra_estimada: mesOpcional,
};

export const obraSchema = z.object({ id: idSchema, ...datos });
export type ObraForm = z.input<typeof obraSchema>;

// "¿Quién?": uno solo, existente o nuevo, y solo con origen referente (OB017).
export const altaSchema = z
  .object({
    ...datos,
    estado: z.enum(ESTADOS_ABIERTOS).default("idea"),
    quien_persona: uuidOpcional,
    quien_empresa: uuidOpcional,
    quien_nuevo_tipo: z.union([z.enum(["persona", "empresa"]), z.literal("")]).nullish().transform((v) => v || null),
    quien_nuevo_nombre: textoOpcional(200),
    quien_nuevo_telefono: telefonoOpcional,
    quien_nuevo_email: emailOpcional,
  })
  .refine(
    (v) => [v.quien_persona, v.quien_empresa, v.quien_nuevo_tipo].filter((q) => q !== null).length <= 1,
    { message: '"¿Quién?" es una sola persona o empresa', path: ["quien_persona"] }
  )
  .refine((v) => v.origen === "referente" || (!v.quien_persona && !v.quien_empresa && !v.quien_nuevo_tipo), {
    message: '"¿Quién?" es para una obra que trae un referente',
    path: ["quien_persona"],
  })
  .refine((v) => v.quien_nuevo_tipo === null || v.quien_nuevo_nombre !== null, {
    message: "El nombre es obligatorio",
    path: ["quien_nuevo_nombre"],
  });
export type AltaForm = z.input<typeof altaSchema>;

// `anterior` solo sirve para pedir la causa al revertir una contratada: la
// regla la hace valer la base (OB009), esto adelanta el mensaje.
export const estadoSchema = z
  .object({
    id: idSchema,
    anterior: z.enum(ESTADOS),
    estado: z.enum(ESTADOS),
    motivo_perdida: z.union([z.enum(MOTIVOS), z.literal("")]).nullish().transform((v) => v || null),
    estado_nota: textoOpcional(2000),
  })
  .refine((v) => v.estado !== "perdida" || v.motivo_perdida !== null, {
    message: "Elegí el motivo",
    path: ["motivo_perdida"],
  })
  .refine((v) => v.motivo_perdida !== "otro" || v.estado_nota !== null, {
    message: "Contá qué pasó",
    path: ["estado_nota"],
  })
  .refine((v) => v.anterior !== "contratada" || v.estado_nota !== null, {
    message: "Contá por qué vuelve atrás",
    path: ["estado_nota"],
  });
export type EstadoForm = z.input<typeof estadoSchema>;

export const transferirSchema = z.object({
  id: idSchema,
  responsable_id: idSchema,
  quedarme: z.boolean().default(false),
});
export type TransferirForm = z.input<typeof transferirSchema>;

export const participanteSchema = z.object({ obra_id: idSchema, usuario_id: idSchema });
export type ParticipanteForm = z.input<typeof participanteSchema>;

// "Es la misma" solo para un alta (OB022) y rechazar con motivo (OB021): los
// hace valer `obras_resolver`; acá se adelanta el mensaje del motivo.
export const resolverSchema = z
  .object({
    id: idSchema,
    decision: z.enum(["aprobar", "rechazar", "es_la_misma"]),
    motivo: textoOpcional(1000),
    existente: uuidOpcional,
  })
  .refine((v) => v.decision !== "rechazar" || v.motivo !== null, {
    message: "Contá por qué se rechaza",
    path: ["motivo"],
  });
export type ResolverForm = z.input<typeof resolverSchema>;

// El aviso a ciegas antes de guardar (`obras_parecidas`): `obra` al editar.
export const parecidasSchema = z.object({ nombre: datos.nombre, direccion: datos.direccion, obra: uuidOpcional });
export type ParecidasForm = z.input<typeof parecidasSchema>;
// id y dirección vienen NULL de las que no ve (el tipo generado no lo dice).
export type ParecidaAviso = { id: string | null; nombre: string; direccion: string | null; responsable: string };

// Los jsonb de `obras_por_aprobar` (sql/139).
export type Parecida = { id: string; nombre: string; direccion: string; responsable: string; coincide: "nombre" | "direccion" };
export type Guardado = { tipo: "persona" | "empresa"; nombre: string; roles: string[] | null };
