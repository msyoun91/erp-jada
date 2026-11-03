import { z } from "zod";
import { Constants, type Database } from "@/lib/supabase/database.types";
import { MONEDAS_LISTA, type Moneda } from "@/lib/monedas";
import type { Nivel } from "@/lib/niveles";
import { idSchema } from "@/lib/validacion";

type Tablas = Database["public"]["Tables"];
type Enums = Database["public"]["Enums"];

export type TipoCatalogo = Enums["tipo_catalogo"];
// Insumos y servicios fijos van en una sola tabla: la pestaña es el tipo.
export type TipoInsumo = Exclude<TipoCatalogo, "paquete">;
export type Unidad = Enums["unidad_insumo"];
export const UNIDADES = Constants.public.Enums.unidad_insumo;

export type Categoria = Pick<Tablas["catalogo_categorias"]["Row"], "id" | "nombre" | "activo">;
export type Color = Pick<Tablas["catalogo_colores"]["Row"], "id" | "nombre" | "activo">;

export type Costo = { costo: number; moneda: Moneda; desde: string };

export type Variante = {
  id: string;
  color_id: string | null;
  activo: boolean;
  // null también para quien no ve costos: la base no los da.
  costo: Costo | null;
};

export type Insumo = Pick<
  Tablas["catalogo_insumos"]["Row"],
  "id" | "nombre" | "categoria_id" | "unidad" | "peso" | "espesor" | "con_color" | "activo"
> & { variantes: Variante[] };

// `catalogo_baja_aviso`: los nombres y el detalle llegan solo con la vista Paquetes.
export type AvisoBaja = {
  salen: number;
  dejan: number;
  salen_nombres?: string[];
  dejan_detalle?: { nombre: string; colores: string[]; piezas: string[]; opciones: string[] }[];
};

export type NivelCosto = {
  variante_id: string;
  costo: number;
  moneda: Moneda;
  anterior: number | null;
  anterior_moneda: Moneda | null;
  nivel: Nivel | null;
};

const nombre = z.string().trim().min(1, "Escribí un nombre").max(120, "Máximo 120 caracteres");
// Un campo numérico vacío llega como null (`setValueAs` del formulario): peso y espesor vacíos no son 0.
const medidaOpcional = z.number("Ingresá un número").min(0, "No puede ser negativo").nullable();
const costo = z.number("Ingresá un número").positive("Tiene que ser mayor que cero");
const moneda = z.enum(MONEDAS_LISTA);

export const categoriaAltaSchema = z.object({ tipo: z.enum(Constants.public.Enums.tipo_catalogo), nombre });
export type CategoriaAltaForm = z.input<typeof categoriaAltaSchema>;

export const nombreAltaSchema = z.object({ nombre });
export const renombrarSchema = z.object({ id: idSchema, nombre });
export type RenombrarForm = z.input<typeof renombrarSchema>;

export const activarSchema = z.object({ id: idSchema, activo: z.boolean() });
export type ActivarForm = z.input<typeof activarSchema>;

// Un solo formulario para alta y edición: el alta lee `colores` (sin ninguno, indistinto) y la
// edición, `con_color`.
export const insumoSchema = z.object({
  nombre,
  categoria_id: z.string().uuid("Elegí una categoría"),
  unidad: z.enum(UNIDADES),
  peso: medidaOpcional,
  espesor: medidaOpcional,
  colores: z.array(idSchema).default([]),
  con_color: z.boolean().default(false),
});
export type InsumoForm = z.input<typeof insumoSchema>;

export const insumoEditarSchema = insumoSchema.extend({ id: idSchema });
export type InsumoEditarForm = z.input<typeof insumoEditarSchema>;

export const fijoSchema = z.object({
  nombre,
  categoria_id: z.string().uuid("Elegí una categoría"),
  unidad: z.enum(UNIDADES),
  costo,
  moneda,
});
export type FijoForm = z.input<typeof fijoSchema>;

export const fijoEditarSchema = fijoSchema
  .pick({ nombre: true, categoria_id: true, unidad: true })
  .extend({ id: idSchema });
export type FijoEditarForm = z.input<typeof fijoEditarSchema>;

export const varianteSchema = z.object({ insumo_id: idSchema, color_id: z.string().uuid("Elegí un color") });
export type VarianteForm = z.input<typeof varianteSchema>;

export const avisoBajaSchema = z.object({ insumo_id: idSchema, variante_id: idSchema.nullable() });
export type AvisoBajaForm = z.input<typeof avisoBajaSchema>;

// Una fila vacía no se guarda: en la carga en bloque se escriben solo las que cambian.
export const costosSchema = z.object({
  filas: z
    .array(z.object({ variante_id: idSchema, costo: costo.nullable(), moneda }))
    .transform((filas) => filas.filter((f): f is typeof f & { costo: number } => f.costo !== null))
    .refine((filas) => filas.length > 0, "Escribí al menos un costo"),
  confirmar_rojo: z.boolean().default(false),
});
export type CostosForm = z.input<typeof costosSchema>;
