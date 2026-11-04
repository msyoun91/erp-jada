import { z } from "zod";
import { Constants, type Database } from "@/lib/supabase/database.types";
import { MONEDAS_LISTA, type Moneda } from "@/lib/monedas";
import type { Nivel } from "@/lib/niveles";
import { idSchema, uuidOpcional } from "@/lib/validacion";

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

// ---------- Servicios en % ----------

export type AlcanceMinimo = Enums["alcance_minimo"];

// El último valor de la historia: la autoridad. `id` es el servicio; `valor_id`, la fila que rige.
export type Porcentaje = {
  id: string;
  valor_id: string;
  nombre: string;
  porcentaje: number;
  paso: number;
  categorias: string[];
  minimo: number | null;
  minimo_moneda: Moneda | null;
  minimo_por: AlcanceMinimo | null;
  opcional: boolean;
  de_baja: boolean;
  desde: string;
};

// El generador declara no-nulas las columnas de un `RETURNS TABLE`: estas pueden llegar en null.
export type FilaHistoria = Omit<Porcentaje, "id" | "valor_id" | "desde"> & {
  id: string;
  revierte_id: string | null;
  cargado_por: string | null;
  nivel: Nivel | null;
  ultimo: boolean;
  created_at: string;
};

// Las categorías solo valen en el paso 1 y el mínimo nunca va en el paso 3: lo que no corresponde se
// limpia acá, para que el formulario pueda esconder el campo sin borrar lo escrito.
export const porcentajeSchema = z
  .object({
    id: idSchema.nullable(),
    nombre,
    porcentaje: z.number("Ingresá un número").positive("Tiene que ser mayor que cero"),
    paso: z.number().int().min(1).max(3),
    categorias: z.array(idSchema).default([]),
    minimo: z.number("Ingresá un número").positive("Tiene que ser mayor que cero").nullable(),
    minimo_moneda: moneda,
    minimo_por: z.enum(Constants.public.Enums.alcance_minimo),
    opcional: z.boolean().default(false),
    confirmar_rojo: z.boolean().default(false),
  })
  .transform((d) => ({
    ...d,
    categorias: d.paso === 1 ? d.categorias : [],
    minimo: d.paso === 3 ? null : d.minimo,
  }));
export type PorcentajeForm = z.input<typeof porcentajeSchema>;

export const revertirSchema = z.object({ valor_id: idSchema, confirmar_rojo: z.boolean().default(false) });
export type RevertirForm = z.input<typeof revertirSchema>;

// ---------- Paquetes y versiones ----------

export type EstadoVersion = Enums["estado_version_catalogo"];
export type AccionVersion = Enums["accion_version_catalogo"];
export type TipoMaterial = Enums["tipo_material"];

export type VersionResumen = {
  id: string;
  numero: number;
  estado: EstadoVersion;
  nombre: string;
  categoria_id: string;
};

export type Paquete = {
  id: string;
  activo: boolean;
  // Por qué está de baja: el insumo o la variante que lo bajó; ninguna de las dos, a mano.
  baja_por: string | null;
  versiones: VersionResumen[];
};

export type ColorVersion = { id: string; color_id: string; nombre: string; base: boolean };

export type FilaHistoriaVersion = {
  id: string;
  accion: AccionVersion;
  motivo: string | null;
  quien: string | null;
  created_at: string;
};

export type Version = VersionResumen & {
  paquete: Paquete;
  colores: ColorVersion[];
  historia: FilaHistoriaVersion[];
};

type Fila<T extends keyof Tablas> = Tablas[T]["Row"];

export type Pieza = Omit<Fila<"catalogo_piezas">, "cantidad_arbol" | "created_at" | "updated_at" | "version_id">;
export type Variable = Omit<Fila<"catalogo_variables">, "formula_arbol" | "created_at" | "updated_at" | "version_id">;
export type Material = Omit<
  Fila<"catalogo_materiales">,
  | "medida_arbol"
  | "ancho_arbol"
  | "alto_arbol"
  | "area_arbol"
  | "cantidad_arbol"
  | "eleccion_arbol"
  | "created_at"
  | "updated_at"
  | "version_id"
>;
export type Opcion = Omit<
  Fila<"catalogo_opciones">,
  | "medida_arbol"
  | "ancho_arbol"
  | "alto_arbol"
  | "area_arbol"
  | "cantidad_arbol"
  | "created_at"
  | "updated_at"
  | "version_id"
>;
export type Condicion = Omit<
  Fila<"catalogo_condiciones">,
  "condicion_arbol" | "created_at" | "updated_at" | "version_id"
>;
export type ValorVariable = { id: string; variable_id: string; opcion_id: string; formula: string };
export type Caso = { id: string; nombre: string; entrada: Entrada };

export type Contenido = {
  piezas: Pieza[];
  variables: Variable[];
  valores: ValorVariable[];
  materiales: Material[];
  opciones: Opcion[];
  condiciones: Condicion[];
  casos: Caso[];
};

// Lo que cargaría un vendedor (`db_schema/catalogo.md` → *La entrada*). La base revisa la forma (CA017).
export const entradaSchema = z.object({
  variables: z.record(z.string(), z.union([z.number(), z.string()])).optional(),
  elecciones: z.record(z.string(), z.record(z.string(), idSchema.nullable())).optional(),
  piezas: z.record(z.string(), z.boolean()).optional(),
  color: idSchema.optional(),
});
export type Entrada = z.infer<typeof entradaSchema>;

export type MensajeDespiece = {
  mensaje: string;
  bloquea: boolean;
  variable_id?: string;
  material_id?: string;
  opcion_id?: string;
};

export type FilaDespiece = {
  pieza_id: string;
  pieza: string;
  material_id: string;
  opcion_id?: string;
  material: string;
  insumo_id: string;
  insumo: string;
  tipo: TipoInsumo;
  categoria_id: string;
  unidad: Unidad;
  color_id?: string;
  color?: string;
  medida?: number;
  ancho?: number;
  alto?: number;
  area?: number;
  cantidad: number;
  total: number;
  // Solo en el detalle del precio.
  costo?: number;
  costo_moneda?: Moneda;
  costo_desde?: string;
  importe?: number;
};

export type PiezaDespiece = {
  id: string;
  nombre: string;
  cantidad: number;
  peso?: number;
  espesor?: number;
  peso_a_produccion: boolean;
  espesor_a_produccion: boolean;
  subtotal?: number;
};

export type Despiece = {
  calculable: boolean;
  bloqueado: boolean;
  mensaje: string | null;
  errores: string[];
  mensajes: MensajeDespiece[];
  color: { id: string; nombre: string } | null;
  variables: { id: string; nombre: string; pieza_id?: string; valor: number | string; a_produccion: boolean }[];
  piezas: PiezaDespiece[];
  filas: FilaDespiece[];
};

export type ServicioPrecio = {
  porcentaje_id: string;
  nombre: string;
  porcentaje: number;
  paso: number;
  opcional: boolean;
  aplica: boolean;
  categorias: string[];
  base: number;
  monto: number;
  minimo?: number;
  minimo_moneda?: Moneda;
  minimo_por?: AlcanceMinimo;
  minimo_convertido?: number;
};

// `catalogo_precio_detalle`: el despiece con costos, servicios y precio, para quien aprueba.
export type PrecioDetalle = Despiece & {
  moneda: Moneda;
  fecha: string;
  costo_despiece: number | null;
  subtotal: number | null;
  servicios: ServicioPrecio[];
  sin_precio: string[];
  precio_exacto: number | null;
  precio: number | null;
};

export type Oferta = {
  color_id: string | null;
  color: string | null;
  armable: boolean;
  piezas_fuera: string[];
  opciones_fuera: string[];
  faltan: string[];
};

export type CasoCalculado = { caso_id: string; nombre: string; resultado: Despiece };

export const paqueteAltaSchema = z.object({ nombre, categoria_id: z.string().uuid("Elegí una categoría") });
export type PaqueteAltaForm = z.input<typeof paqueteAltaSchema>;

export const duplicarSchema = z.object({ version_id: idSchema, nombre });
export type DuplicarForm = z.input<typeof duplicarSchema>;

export const versionNuevaSchema = z.object({ paquete_id: idSchema, origen_id: idSchema });
export type VersionNuevaForm = z.input<typeof versionNuevaSchema>;

export const devolverSchema = z.object({
  version_id: idSchema,
  motivo: z.string().trim().min(1, "Escribí el motivo: Técnica lo lee al abrir el borrador").max(2000),
});
export type DevolverForm = z.input<typeof devolverSchema>;

export const calcularSchema = z.object({
  version_id: idSchema,
  entrada: entradaSchema,
  // Solo con `catalogo_aprobar`: el precio y, si la hay, la publicada con la misma entrada y fecha.
  precio: z
    .object({
      moneda,
      opcionales: z.array(idSchema),
      comparar_con: idSchema.nullable(),
    })
    .nullable(),
});
export type CalcularForm = z.input<typeof calcularSchema>;

export type InsumoBasico = {
  id: string;
  nombre: string;
  tipo: TipoInsumo;
  unidad: Unidad;
  categoria_id: string;
  con_color: boolean;
  activo: boolean;
};

export type PrecioReferencia = {
  paquete_id: string;
  version_id: string;
  numero: number;
  nombre: string;
  caso_id: string;
  caso: string;
  precio_desde: number | null;
  precio_hasta: number | null;
  cambio: number | null;
  sin_precio_desde: string[];
  sin_precio_hasta: string[];
};

// ---------- Editor del borrador ----------
// Cada schema limpia lo que no corresponde al tipo, así el CHECK de la base (`sql/160`) no salta por un
// campo escondido. Lo que puede quedar a medias en un borrador no se valida acá: lo frena el envío.

export const TIPOS_MATERIAL = Constants.public.Enums.tipo_material;

const formula = z
  .string()
  .trim()
  .max(2000, "Máximo 2000 caracteres")
  .nullish()
  .transform((v) => v || null);
const cantidad = z
  .string()
  .trim()
  .max(2000, "Máximo 2000 caracteres")
  .nullish()
  .transform((v) => v || "1");
const numeroNulo = z.number("Ingresá un número").nullable();
const nuevoOId = { id: idSchema.nullable(), version_id: idSchema, orden: z.number().int().default(0) };

export const versionDatosSchema = z.object({
  id: idSchema,
  nombre,
  categoria_id: z.string().uuid("Elegí una categoría"),
});
export type VersionDatosForm = z.input<typeof versionDatosSchema>;

export const colorVersionSchema = z.object({ version_id: idSchema, color_id: z.string().uuid("Elegí un color") });
export type ColorVersionForm = z.input<typeof colorVersionSchema>;

export const piezaSchema = z
  .object({
    ...nuevoOId,
    nombre,
    cantidad,
    opcional: z.boolean().default(false),
    incluida: z.boolean().default(false),
    requiere_pieza_id: uuidOpcional,
    secundario: z.boolean().default(false),
    calcula_espesor: z.boolean().default(false),
    peso_a_produccion: z.boolean().default(true),
    espesor_a_produccion: z.boolean().default(true),
  })
  .transform((d) => (d.opcional ? d : { ...d, incluida: false, secundario: false, requiere_pieza_id: null }));
export type PiezaForm = z.input<typeof piezaSchema>;

export const variableSchema = z
  .object({
    ...nuevoOId,
    pieza_id: uuidOpcional,
    nombre,
    ingresa_vendedor: z.boolean().default(false),
    es_lista: z.boolean().default(false),
    formula,
    // En el formulario, uno por renglón; ya separados también valen, así el schema se puede volver a aplicar
    // sobre su propia salida (la action recibe lo que validó el formulario).
    valores: z.union([z.string(), z.array(z.string())]).default(""),
    valor_predeterminado: z
      .string()
      .trim()
      .nullish()
      .transform((v) => v || null),
    es_cantidad: z.boolean().default(false),
    minimo: numeroNulo,
    maximo: numeroNulo,
    secundario: z.boolean().default(false),
    a_produccion: z.boolean().default(true),
    segun_material_id: uuidOpcional,
  })
  .refine((d) => d.ingresa_vendedor || d.segun_material_id || d.formula, {
    path: ["formula"],
    message: "Si no la carga el vendedor, lleva una fórmula",
  })
  .transform((d) => {
    const renglones = typeof d.valores === "string" ? d.valores.split("\n") : d.valores;
    const valores = [...new Set(renglones.map((v) => v.trim()).filter(Boolean))];
    if (!d.ingresa_vendedor) {
      return {
        ...d,
        es_lista: false,
        es_cantidad: false,
        minimo: null,
        maximo: null,
        secundario: false,
        valores: [],
        valor_predeterminado: null,
      };
    }
    if (d.es_lista) {
      const pred = d.valor_predeterminado && valores.includes(d.valor_predeterminado) ? d.valor_predeterminado : null;
      return {
        ...d,
        segun_material_id: null,
        formula: null,
        es_cantidad: false,
        minimo: null,
        maximo: null,
        valores,
        valor_predeterminado: pred,
      };
    }
    return { ...d, segun_material_id: null, valores: [], valor_predeterminado: null };
  });
export type VariableForm = z.input<typeof variableSchema>;

export const valorVariableSchema = z.object({
  id: idSchema.nullable(),
  version_id: idSchema,
  variable_id: idSchema,
  opcion_id: idSchema,
  formula: z.string().trim().min(1, "Escribí un número o una fórmula").max(2000, "Máximo 2000 caracteres"),
});
export type ValorVariableForm = z.input<typeof valorVariableSchema>;

export const materialSchema = z
  .object({
    ...nuevoOId,
    pieza_id: idSchema,
    tipo: z.enum(TIPOS_MATERIAL),
    nombre: z
      .string()
      .trim()
      .max(120, "Máximo 120 caracteres")
      .nullish()
      .transform((v) => v || null),
    insumo_id: uuidOpcional,
    medida: formula,
    ancho: formula,
    alto: formula,
    area: formula,
    cantidad,
    eleccion: formula,
    sin_eleccion: z.boolean().default(false),
    sigue_material_id: uuidOpcional,
    secundario: z.boolean().default(false),
    cuenta_peso: z.boolean().default(true),
    cuenta_espesor: z.boolean().default(false),
  })
  .refine((d) => d.tipo === "unico" || d.nombre, {
    path: ["nombre"],
    message: "Un material múltiple lleva el nombre que lee el vendedor",
  })
  .transform((d) => ({
    ...d,
    nombre: d.tipo === "unico" ? null : d.nombre,
    insumo_id: d.tipo === "unico" ? d.insumo_id : null,
    eleccion: d.tipo === "elige_sistema" ? d.eleccion : null,
    sigue_material_id: d.tipo === "sigue" ? d.sigue_material_id : null,
    sin_eleccion: d.tipo === "elige_vendedor" && d.sin_eleccion,
    secundario: (d.tipo === "elige_vendedor" || d.tipo === "sigue") && d.secundario,
  }));
export type MaterialForm = z.input<typeof materialSchema>;

// Una opción vacía hereda del material, cada dato por separado; la cantidad también.
export const opcionSchema = z.object({
  ...nuevoOId,
  material_id: idSchema,
  insumo_id: uuidOpcional,
  sigue_opcion_id: uuidOpcional,
  predeterminada: z.boolean().default(false),
  medida: formula,
  ancho: formula,
  alto: formula,
  area: formula,
  cantidad: formula,
});
export type OpcionForm = z.input<typeof opcionSchema>;

export const condicionSchema = z.object({
  id: idSchema.nullable(),
  version_id: idSchema,
  variable_id: uuidOpcional,
  material_id: uuidOpcional,
  opcion_id: uuidOpcional,
  condicion: z.string().trim().min(1, "Escribí la condición, como ancho > 3000").max(2000),
  mensaje: z.string().trim().min(1, "Escribí el mensaje que lee el vendedor").max(500),
  bloquea: z.boolean().default(false),
});
export type CondicionForm = z.input<typeof condicionSchema>;

export const casoSchema = z.object({ version_id: idSchema, nombre, entrada: entradaSchema });
export type CasoForm = z.input<typeof casoSchema>;

export const TABLAS_CONTENIDO = [
  "catalogo_piezas",
  "catalogo_variables",
  "catalogo_variables_valores",
  "catalogo_materiales",
  "catalogo_opciones",
  "catalogo_condiciones",
  "catalogo_casos",
  "catalogo_versiones_colores",
] as const;
export type TablaContenido = (typeof TABLAS_CONTENIDO)[number];

export const sacarSchema = z.object({ tabla: z.enum(TABLAS_CONTENIDO), id: idSchema });
export type SacarForm = z.input<typeof sacarSchema>;

export const ordenarSchema = z.object({
  tabla: z.enum(["catalogo_piezas", "catalogo_variables", "catalogo_materiales", "catalogo_opciones"]),
  ids: z.array(idSchema).min(1),
});
export type OrdenarForm = z.input<typeof ordenarSchema>;
