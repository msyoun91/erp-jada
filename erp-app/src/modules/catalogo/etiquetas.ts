import { formatMonto } from "@/lib/monedas";
import type { AvisoBaja, Costo, Unidad } from "./types";

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
