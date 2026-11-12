import { z } from "zod";
import {
  desdeEntrada,
  entradaSchema,
  numeroEscrito,
  type Entrada,
  type EntradaEstado,
  type FormularioEntrada,
  type MaterialEntrada,
  type PiezaEntrada,
  type VariableEntrada,
} from "@/lib/entrada";
import { formatMontoCliente, MONEDAS_LISTA } from "@/lib/monedas";
import { Constants, type Database } from "@/lib/supabase/database.types";
import { idSchema, textoOpcional } from "@/lib/validacion";

type Enums = Database["public"]["Enums"];

export const ALICUOTAS = [21, 10.5, 0] as const;

export function formatAlicuota(alicuota: number) {
  return `${String(alicuota).replace(".", ",")} %`;
}

const alicuotaSchema = z.coerce.number().refine((v) => (ALICUOTAS as readonly number[]).includes(v), "Alícuota inválida");

const dosDecimales = (n: number) => Math.abs(n * 100 - Math.round(n * 100)) < 1e-6;

// Vacío no es cero: coerce solo leía "" como 0. Llega como texto del panel y como número a la acción.
function numeroRequerido(mensaje: string) {
  return z.union([z.number(), z.string().trim().min(1, mensaje)]);
}

export const configuracionSchema = z.object({
  tope_descuento: numeroRequerido("Escribí el tope").pipe(
    z.coerce
      .number<string | number>("Ingresá un número")
      .min(0, "No puede ser negativo")
      .max(100, "Hasta 100 %")
      .refine(dosDecimales, "Hasta 2 decimales"),
  ),
  plazo_dias: numeroRequerido("Escribí el plazo").pipe(
    z.coerce.number<string | number>("Ingresá un número").int("En días enteros").min(1, "Al menos 1 día").max(365, "Hasta 365 días"),
  ),
  monedas_referencia: z.array(z.enum(MONEDAS_LISTA)),
  terminos: z.string().trim().max(5000, "Máximo 5000 caracteres"),
});
export type ConfiguracionForm = z.input<typeof configuracionSchema>;

// Una ventana sin guardar, la de la calculadora de venta: se calcula y se lleva a un presupuesto nuevo.
export const ventanaSchema = z.object({
  paquete_id: z.string().uuid("Elegí el paquete"),
  entrada: entradaSchema,
  opcionales: z.array(idSchema),
  moneda: z.enum(MONEDAS_LISTA),
});
export type VentanaForm = z.input<typeof ventanaSchema>;

// Con `ventana`, va en la sección nueva, en la moneda de la sección (`presupuestos_alta`).
export const altaSchema = z.object({
  obra: idSchema,
  nombre: z.string().trim().min(1, "Escribí el nombre").max(200, "Máximo 200 caracteres"),
  moneda: z.enum(MONEDAS_LISTA),
  alicuota: alicuotaSchema,
  seccion: z.string().trim().max(100, "Máximo 100 caracteres"),
  ventana: ventanaSchema.omit({ moneda: true }).optional(),
});
export type AltaForm = z.input<typeof altaSchema>;

export const nombreSchema = altaSchema.pick({ nombre: true }).extend({ id: idSchema });
export type NombreForm = z.input<typeof nombreSchema>;

export const aprobarSchema = z.object({ version: z.string().uuid("Elegí la variante que aprobó el cliente") });
export type AprobarForm = z.input<typeof aprobarSchema>;

// Con "otro", el detalle (PR022); la nota va de 1 a 500.
export const rechazarSchema = z
  .object({
    id: idSchema,
    motivo: z.enum(Constants.public.Enums.motivo_perdida, "Elegí el motivo"),
    detalle: textoOpcional(500),
  })
  .refine((v) => v.motivo !== "otro" || v.detalle !== null, { message: "Contá qué pasó", path: ["detalle"] });
export type RechazarForm = z.input<typeof rechazarSchema>;

export const revertirSchema = z.object({
  id: idSchema,
  causa: z.string().trim().min(1, "Escribí por qué se revierte").max(500, "Máximo 500 caracteres"),
});
export type RevertirForm = z.input<typeof revertirSchema>;

// Vencida se calcula, no se guarda: sigue publicada (decisiones/presupuestos.md → *Precio*).
export function estaVencida(v: { estado: Enums["estado_version_presupuesto"]; vence: string | null }, hoy: string) {
  return v.estado === "publicado" && v.vence !== null && v.vence < hoy;
}

export const datosVersionSchema = z.object({
  id: idSchema,
  variante_nombre: z.string().trim().max(100, "Máximo 100 caracteres"),
  iva_discriminado: z.boolean(),
  descuento: z.coerce.number("Ingresá un número").min(0, "No puede ser negativo").max(100, "Hasta 100 %"),
  condiciones: z.string().trim().max(3000, "Máximo 3000 caracteres"),
});
export type DatosVersionForm = z.input<typeof datosVersionSchema>;

export const seccionSchema = z.object({
  id: idSchema.optional(),
  version_id: idSchema,
  nombre: z.string().trim().min(1, "Escribí el nombre").max(100, "Máximo 100 caracteres"),
  moneda: z.enum(MONEDAS_LISTA),
  alicuota: alicuotaSchema,
  orden: z.number().int(),
});
export type SeccionForm = z.input<typeof seccionSchema>;

// "" deja como está: `z.literal("")` va primero, porque coerce lo leería como 0 %.
export const todasSeccionesSchema = z
  .object({
    version_id: idSchema,
    moneda: z.union([z.literal(""), z.enum(MONEDAS_LISTA)]),
    alicuota: z.union([z.literal(""), alicuotaSchema]),
  })
  .refine((d) => d.moneda !== "" || d.alicuota !== "", { message: "Elegí la moneda o el IVA", path: ["moneda"] });
export type TodasSeccionesForm = z.input<typeof todasSeccionesSchema>;

const renglonBase = {
  id: idSchema.optional(),
  version_id: idSchema,
  seccion_id: z.string().uuid("Elegí la sección"),
  designacion: textoOpcional(30),
  ubicacion: textoOpcional(100),
  cantidad: z.coerce.number("Ingresá un número").positive("Tiene que ser mayor que 0"),
};

// El precio escrito, por unidad y sin IVA, en la moneda de la sección. Vacío no es cero, y como las medidas, va sin
// puntos: con `type="number"`, "150.000" quedaba en 150 (`decisiones/catalogo/despiece.md` → *En la calculadora…*).
export const renglonManoSchema = z.object({
  ...renglonBase,
  descripcion: z.string().trim().min(1, "Escribí la descripción").max(500, "Máximo 500 caracteres"),
  precio: z
    .union([z.number(), z.string()])
    .transform((v, ctx) => {
      const n = typeof v === "number" ? v : numeroEscrito(v);
      if (n !== null) return n;
      ctx.addIssue({
        code: "custom",
        message: String(v).trim() ? "Va sin puntos y con coma para el decimal: 150000 o 1500,5" : "Escribí el precio",
      });
      return z.NEVER;
    })
    .pipe(
      z
        .number("Ingresá un número")
        .min(0, "No puede ser negativo")
        .refine(dosDecimales, "Hasta 2 decimales"),
    ),
});
export type RenglonManoForm = z.input<typeof renglonManoSchema>;

// `entrada` y `opcionales` van solo si se tocaron: reescribir lo cargado de una ventana que no cambió no tiene por qué
// pasar por el precio de hoy (`presupuestos_renglones_validar`). Uno nuevo los lleva siempre. El panel valida los campos;
// lo cargado lo suma al enviar.
export const renglonCatalogoCampos = z.object({
  ...renglonBase,
  paquete_id: z.string().uuid("Elegí el paquete"),
  entrada: entradaSchema.optional(),
  opcionales: z.array(idSchema).optional(),
});
export const renglonCatalogoSchema = renglonCatalogoCampos
  .refine((d) => !!d.id || (!!d.entrada && !!d.opcionales), { message: "Falta lo cargado", path: ["paquete_id"] });
export type RenglonCatalogoForm = z.input<typeof renglonCatalogoSchema>;

// Lo que da `catalogo_venta_formulario` (`db_schema/catalogo.md` → *El precio*). Desde `sql/196`, todas las piezas.
export type FormularioVenta = {
  version_id: string;
  piezas: PiezaEntrada[];
  variables: (VariableEntrada & { predeterminado: number | string | null })[];
  materiales: MaterialEntrada[];
  opciones: { id: string; material_id: string; insumo_id: string | null; predeterminada: boolean; nombre: string | null }[];
  // Sin colores, una fila con `id` NULL.
  colores: { id: string | null; nombre: string | null; base: boolean; piezas_fuera: string[]; opciones_fuera: string[] }[];
  servicios: { id: string; nombre: string }[];
};

// El predeterminado va como se escribe (coma decimal, sin miles): con "1.200" el vendedor copiaba un punto que el campo
// rechaza.
export function aFormularioEntrada(f: FormularioVenta): FormularioEntrada {
  return {
    piezas: f.piezas,
    variables: f.variables.map((v) => ({
      ...v,
      predeterminado: v.predeterminado === null ? null : String(v.predeterminado).replace(".", ","),
    })),
    materiales: f.materiales,
    opciones: f.opciones.map((o) => ({ ...o, nombre: o.nombre ?? "" })),
    colores: f.colores.flatMap((c) => (c.id ? [{ ...c, id: c.id, nombre: c.nombre ?? "" }] : [])),
  };
}

// Lo cargado pasa al paquete nuevo por nombre: el ancho y el alto no se escriben de nuevo. Un color o un insumo que el
// nuevo no ofrece no pasa: el select lo mostraría vacío y la entrada lo mandaría igual.
export function pasarAPaquete(antes: Entrada, f: FormularioVenta): EntradaEstado {
  const nuevo = desdeEntrada(antes, f);
  if (!f.colores.some((c) => c.id === nuevo.color)) nuevo.color = "";
  for (const [material, insumo] of Object.entries(nuevo.elecciones)) {
    if (insumo !== "ninguna" && !f.opciones.some((o) => o.material_id === material && o.insumo_id === insumo)) {
      delete nuevo.elecciones[material];
    }
  }
  return nuevo;
}

// Lo que da `catalogo_precio`: lo que se vende hoy, sin IVA. Sin precio, `mensaje` dice por qué, o un bloqueo en `mensajes`.
export type PrecioCatalogo = { precio: number | null; mensaje: string | null; mensajes: MensajeCatalogo[] | null };

// Los opcionales de un paquete, con la clave de `presupuestos_clave`: la pieza por nombre en toda la versión (cada paquete
// tiene la suya), el servicio por id. `id`: el de la pieza en esa versión del paquete, o el del servicio.
export type Opcional = { clave: string; nombre: string; tipo: "pieza" | "servicio"; id: string };

export function opcionalesDe(f: FormularioVenta): Opcional[] {
  return [
    ...f.piezas
      .filter((p) => p.opcional)
      .map((p) => ({ clave: `pieza:${p.nombre.trim().toLowerCase()}`, nombre: p.nombre, tipo: "pieza" as const, id: p.id })),
    ...f.servicios.map((s) => ({ clave: `servicio:${s.id}`, nombre: s.nombre, tipo: "servicio" as const, id: s.id })),
  ];
}

// Cómo se ve: "precio" (sin fila), "debajo", o el id de la sección del renglón aparte.
const comoSchema = z.union([z.literal("precio"), z.literal("debajo"), idSchema]);

// Va la lista entera con cómo estaba cada uno: la acción escribe solo los que cambiaron.
export const opcionalesSchema = z.object({
  version_id: idSchema,
  opcionales: z.array(
    z
      .object({
        fila: idSchema.nullable(),
        pieza: z.string().trim().min(1).max(100).nullable(),
        porcentaje_id: idSchema.nullable(),
        inicial: comoSchema,
        como: comoSchema,
      })
      .refine((o) => (o.pieza === null) !== (o.porcentaje_id === null), "Pieza o servicio, uno"),
  ),
});
export type OpcionalesForm = z.input<typeof opcionalesSchema>;

const ESTADO_VERSION = {
  borrador: { label: "Borrador", badge: "badge-neutral" },
  en_revision: { label: "En revisión", badge: "badge-warning" },
  publicado: { label: "Publicada", badge: "badge-brand" },
  obsoleto: { label: "Reemplazada", badge: "badge-neutral" },
} as const;

// "Aprobada" e "Inhabilitada" no se guardan: salen de la versión que eligió el presupuesto (decisiones/presupuestos.md →
// *Estados y versiones*).
export function estadoVersion(
  v: { id: string; estado: Enums["estado_version_presupuesto"] },
  p: { estado: Enums["estado_presupuesto"]; version_aprobada_id: string | null },
): { label: string; badge: string } {
  if (p.version_aprobada_id === v.id) return { label: "Aprobada", badge: "badge-success" };
  if (p.estado === "aprobado" && v.estado === "publicado") return { label: "Inhabilitada", badge: "badge-neutral" };
  return ESTADO_VERSION[v.estado];
}

// Lo que pide autorización, como lo da `presupuestos_version_pedido` y como queda en `presupuestos_autorizaciones.pedido`.
// Montos sin IVA, con el recargo; `diferencia` es a hoy menos mantenido.
export type PedidoComercial = {
  renglones: {
    renglon_id: string;
    etiqueta: string;
    moneda: Enums["moneda"];
    cantidad: number;
    precio: number | null;
    hoy: number | null;
    condiciones_en: string | null;
    diferencia: number | null;
  }[];
  diferencia: { moneda: Enums["moneda"]; monto: number }[];
  // NULL si no pasa el tope.
  descuento: number | null;
  tope: number;
  texto: string;
};
export type PedidoTecnica = { etiqueta: string; motivos: string[]; texto: string };

// En borrador, lo que se va a pedir (`id` NULL; `estado` NULL si falta pedirlo, o `autorizada` si ya lo cubre una de
// Técnica); en revisión, las filas del último pedido.
export type AutorizacionVersion = {
  id: string | null;
  estado: "pendiente" | "autorizada" | null;
  pedido_por: string | null;
  pedido_en: string | null;
  resuelto_por: string | null;
  resuelto_en: string | null;
} & ({ tipo: "comercial"; pedido: PedidoComercial } | { tipo: "tecnica"; pedido: PedidoTecnica });

export const devolverSchema = z.object({
  id: idSchema,
  motivo: z.string().trim().min(1, "Escribí el motivo: lo lee quien la armó").max(500, "Máximo 500 caracteres"),
});
export type DevolverForm = z.input<typeof devolverSchema>;

// Lo que va debajo de una ventana, como lo da `presupuestos_version_importes`.
export type LineaDebajo = { clave: string; nombre: string; importe: number; importe_con_iva: number };

// Alertas y bloqueos del paquete, como los da `catalogo_precio`.
export type MensajeCatalogo = { mensaje: string; bloquea: boolean };

// Lo cargado en una ventana, para Técnica: "Ancho 2600 · Alto 2100 · Bronce · Vidrio: DVH 4/9/4 · con Mosquitero". Solo lo
// que escribió el vendedor (lo demás tomó el predeterminado); el color y lo elegido, si se leen sus nombres. Las medidas, en el
// orden del paquete si se lee: el `jsonb` las da por largo del nombre, alto antes que ancho.
export function textoCargado(
  e: Entrada,
  nombres: Map<string, string>,
  orden: (variable: string) => number | undefined,
): string | null {
  const ultimo = Number.MAX_SAFE_INTEGER;
  const partes = [
    ...Object.entries(e.variables ?? {})
      .sort(([a], [b]) => (orden(a) ?? ultimo) - (orden(b) ?? ultimo))
      .map(([n, v]) => `${n} ${String(v).replace(".", ",")}`),
    e.color && nombres.get(e.color),
    ...Object.values(e.elecciones ?? {}).flatMap((m) =>
      Object.entries(m).map(([material, insumo]) =>
        insumo === null ? `sin ${material}` : nombres.has(insumo) && `${material}: ${nombres.get(insumo)}`,
      ),
    ),
    ...Object.entries(e.piezas ?? {}).map(([p, si]) => `${si ? "con" : "sin"} ${p}`),
  ];
  const texto = [...new Set(partes.filter((p): p is string => !!p))].join(" · ");
  return texto || null;
}

export type IvaTotal = { alicuota: number; monto: number };

// Un importe de `presupuestos_version_importes`: NULL, sin precio.
export type Monto = { importe: number | null; importe_con_iva: number | null };

// Con IVA incluido se muestra el importe con IVA que da la base, no uno recalculado en pantalla (*Pantallas*).
export function montoVisible(m: Monto, moneda: Enums["moneda"], conIva: boolean): string | null {
  const valor = conIva ? m.importe_con_iva : m.importe;
  return valor === null ? null : formatMontoCliente(valor, moneda);
}

// El renglón aparte de un opcional: la suma de ese opcional en todas las ventanas. Sin precio si alguna no lo tiene.
export function sumarMontos(filas: Monto[]): Monto {
  const suma = (k: keyof Monto) => (filas.some((f) => f[k] === null) ? null : filas.reduce((s, f) => s + (f[k] ?? 0), 0));
  return { importe: suma("importe"), importe_con_iva: suma("importe_con_iva") };
}

export const eleccionSchema = z.object({
  texto: z.string().trim().min(1, "Pegá el link o el mensaje del cliente").max(5000, "El texto es demasiado largo"),
});
export type EleccionForm = z.infer<typeof eleccionSchema>;

const totalSchema = z.object({
  moneda: z.enum(MONEDAS_LISTA),
  total: z.number(),
  sin_precio: z.number(),
});
export type TotalEleccion = z.infer<typeof totalSchema>;

export const eleccionLeidaSchema = z.object({
  presupuesto_id: z.string(),
  codigo: z.string(),
  version_id: z.string(),
  numero: z.number(),
  variante_nombre: z.string().nullable(),
  descarta: z.object({ numero: z.number(), estado: z.string() }).nullable(),
  ventanas: z.array(
    z.object({
      renglon_id: z.string(),
      etiqueta: z.string(),
      casillas: z.array(z.object({ clave: z.string(), nombre: z.string() })),
      antes: z.array(z.string()),
      despues: z.array(z.string()),
    }),
  ),
  cliente: z.array(totalSchema),
});
export type EleccionLeida = z.infer<typeof eleccionLeidaSchema>;

export const eleccionAplicadaSchema = z.object({
  version_id: z.string(),
  numero: z.number(),
  descartada: z.number().nullable(),
  cliente: z.array(totalSchema),
  publicada: z.array(totalSchema),
  hoy: z.array(totalSchema),
});
export type EleccionAplicada = z.infer<typeof eleccionAplicadaSchema>;
