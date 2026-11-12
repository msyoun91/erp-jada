import type { Combinacion, Version } from "./tipos";

export type Total = { moneda: string; subtotal: number; descuento: number; iva: number; total: number; sinPrecio: number };

const redondear = (monto: number, moneda: string) => {
  const f = moneda === "ARS" ? 1 : 100;
  return Math.round(monto * f) / f;
};

// Muestra el total de lo tildado con la regla del ERP (presupuestos_totales_de); el que vale lo recalcula el ERP al aplicar.
export function totalesDe(v: Version, elegidas: Record<string, Combinacion>): Total[] {
  const secciones = new Map(v.secciones.map((s) => [s.id, s]));
  const grupos = new Map<string, { moneda: string; alicuota: number; base: number; sinPrecio: number }>();
  const sumar = (seccionId: string, importe: number | null) => {
    const s = secciones.get(seccionId);
    if (!s) return;
    const k = `${s.moneda}|${s.alicuota}`;
    const g = grupos.get(k) ?? { moneda: s.moneda, alicuota: s.alicuota, base: 0, sinPrecio: 0 };
    if (importe === null) g.sinPrecio += 1;
    else g.base += importe;
    grupos.set(k, g);
  };
  for (const r of v.renglones) {
    const c = elegidas[r.id];
    if (!c) continue;
    sumar(r.seccion_id, c.importe);
    for (const a of c.aparte) sumar(a.seccion_id, a.importe);
  }
  const porMoneda = new Map<string, Total>();
  for (const g of grupos.values()) {
    const rebaja = redondear((g.base * v.descuento) / 100, g.moneda);
    const impuesto = redondear(((g.base - rebaja) * g.alicuota) / 100, g.moneda);
    const t = porMoneda.get(g.moneda) ?? { moneda: g.moneda, subtotal: 0, descuento: 0, iva: 0, total: 0, sinPrecio: 0 };
    t.subtotal += g.base;
    t.descuento += rebaja;
    t.iva += impuesto;
    t.total += g.base - rebaja + impuesto;
    t.sinPrecio += g.sinPrecio;
    porMoneda.set(g.moneda, t);
  }
  return [...porMoneda.values()].sort((a, b) => a.moneda.localeCompare(b.moneda));
}
