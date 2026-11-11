import { z } from "zod";
import {
  entradaSchema,
  numeroEscrito,
  type FormularioEntrada,
  type MaterialEntrada,
  type PiezaEntrada,
  type VariableEntrada,
} from "@/lib/entrada";
import { MONEDAS_LISTA } from "@/lib/monedas";
import type { Database } from "@/lib/supabase/database.types";
import { idSchema, textoOpcional } from "@/lib/validacion";

type Enums = Database["public"]["Enums"];

export const ALICUOTAS = [21, 10.5, 0] as const;

export function formatAlicuota(alicuota: number) {
  return `${String(alicuota).replace(".", ",")} %`;
}

const alicuotaSchema = z.coerce.number().refine((v) => (ALICUOTAS as readonly number[]).includes(v), "Alícuota inválida");

export const altaSchema = z.object({
  obra: idSchema,
  nombre: z.string().trim().min(1, "Escribí el nombre").max(200, "Máximo 200 caracteres"),
  moneda: z.enum(MONEDAS_LISTA),
  alicuota: alicuotaSchema,
  seccion: z.string().trim().max(100, "Máximo 100 caracteres"),
});
export type AltaForm = z.input<typeof altaSchema>;

export const nombreSchema = altaSchema.pick({ nombre: true }).extend({ id: idSchema });
export type NombreForm = z.input<typeof nombreSchema>;

export const datosVersionSchema = z.object({
  id: idSchema,
  variante_nombre: z.string().trim().max(100, "Máximo 100 caracteres"),
  iva_discriminado: z.boolean(),
  descuento: z.coerce.number("Ingresá un número").min(0, "No puede ser negativo").max(100, "Hasta 100 %"),
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
        .refine((n) => Math.abs(n * 100 - Math.round(n * 100)) < 1e-6, "Hasta 2 decimales"),
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

export type IvaTotal = { alicuota: number; monto: number };
