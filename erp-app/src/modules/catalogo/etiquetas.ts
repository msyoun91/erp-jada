import { formatMonto, type Moneda } from "@/lib/monedas";
import type { AlcanceMinimo, AvisoBaja, Costo, Unidad } from "./types";

export const UNIDAD: Record<Unidad, string> = { mm: "mm", m2: "m2", u: "u" };

// Las fórmulas dan mm, pero el costo y el peso de un insumo en mm van por metro
// (`decisiones/catalogo/insumos.md` → *Las fórmulas se escriben en mm*).
export const POR_UNIDAD: Record<Unidad, string> = { mm: "m", m2: "m2", u: "u" };

export function textoCosto(c: Costo, unidad: Unidad): string {
  return `${formatMonto(c.costo, c.moneda)} /${POR_UNIDAD[unidad]}`;
}

export function textoNumero(n: number): string {
  return n.toLocaleString("es-AR", { maximumFractionDigits: 4 });
}

const MES = 30 * 86_400_000;

// "hace 9 meses": un costo en pesos de hace un año da un precio creíble y equivocado.
export function hace(iso: string): string {
  const ms = Date.now() - new Date(iso).getTime();
  const dias = Math.floor(ms / 86_400_000);
  if (dias < 1) return "hoy";
  if (dias < 30) return dias === 1 ? "hace 1 día" : `hace ${dias} días`;
  const meses = Math.floor(ms / MES);
  if (meses < 12) return meses === 1 ? "hace 1 mes" : `hace ${meses} meses`;
  const anios = Math.floor(meses / 12);
  return anios === 1 ? "hace 1 año" : `hace ${anios} años`;
}

// Con la misma forma que la base guarda en `catalogo_bajas.dejan`: `Puerta balcón (Negro, DVH)`.
export function lineasBaja(a: AvisoBaja): string[] {
  const lineas: string[] = [];
  if (a.salen > 0) {
    lineas.push(`Salen de la venta (${a.salen})${a.salen_nombres ? `: ${a.salen_nombres.join(", ")}` : ""}`);
  }
  if (a.dejan > 0) {
    const detalle = a.dejan_detalle?.map(
      (d) => `${d.nombre} (${[...d.colores, ...d.piezas, ...d.opciones].join(", ")})`,
    );
    lineas.push(`Dejan de ofrecer algo (${a.dejan})${detalle ? `: ${detalle.join("; ")}` : ""}`);
  }
  return lineas;
}

// ---------- Servicios en % ----------

export const PASO: Record<number, { titulo: string; ayuda: string }> = {
  1: {
    titulo: "Paso 1 · Sobre el despiece",
    ayuda: "Todo el despiece, o solo los insumos y servicios fijos de ciertas categorías.",
  },
  2: { titulo: "Paso 2 · Sobre el subtotal", ayuda: "El despiece más lo del paso 1." },
  3: {
    titulo: "Paso 3 · Sobre el precio final",
    ayuda: "Despejado para que sea el % exacto del precio. Los del paso 3 suman menos de 100 %.",
  },
};

export function textoBase(p: { paso: number; categorias: string[] }, nombreCategoria: Map<string, string>): string {
  if (p.paso === 2) return "sobre el subtotal";
  if (p.paso === 3) return "sobre el precio final";
  if (p.categorias.length === 0) return "sobre todo el despiece";
  return `sobre ${p.categorias.map((c) => nombreCategoria.get(c) ?? "una categoría que no existe").join(", ")}`;
}

export function textoMinimo(p: {
  minimo: number | null;
  minimo_moneda: Moneda | null;
  minimo_por: AlcanceMinimo | null;
}): string | null {
  if (p.minimo === null || !p.minimo_moneda || !p.minimo_por) return null;
  return `mínimo ${formatMonto(p.minimo, p.minimo_moneda)} por ${p.minimo_por}`;
}

export function textoPorcentaje(n: number): string {
  return `${n.toLocaleString("es-AR", { maximumFractionDigits: 3 })} %`;
}
