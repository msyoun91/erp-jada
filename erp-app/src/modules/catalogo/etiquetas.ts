import { formatMonto, type Moneda } from "@/lib/monedas";
import type {
  AccionVersion,
  AlcanceMinimo,
  AvisoBaja,
  Costo,
  EstadoVersion,
  FilaDespiece,
  Paquete,
  Unidad,
  VersionResumen,
} from "./types";

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

// ---------- Paquetes y versiones ----------

export const ESTADO_VERSION: Record<EstadoVersion, { label: string; badge: string }> = {
  borrador: { label: "En borrador", badge: "badge-warning" },
  en_revision: { label: "En revisión", badge: "badge-info" },
  publicado: { label: "Publicada", badge: "badge-success" },
  obsoleto: { label: "Obsoleta", badge: "badge-neutral" },
  descartado: { label: "Descartada", badge: "badge-neutral" },
};

export const ACCION_VERSION: Record<AccionVersion, string> = {
  enviada: "Enviada a revisión",
  retirada: "Retirada de revisión",
  devuelta: "Devuelta",
  aprobada: "Aprobada",
  obsoleta: "Pasó a obsoleta",
  descartada: "Descartada",
};

// Lo que el vendedor ve de un paquete: la publicada; sin publicada, la última.
export function versionPrincipal(p: Paquete): VersionResumen | undefined {
  return p.versiones.find((v) => v.estado === "publicado") ?? p.versiones[0];
}

export function textoMedida(n: number): string {
  return n.toLocaleString("es-AR", { maximumFractionDigits: 2 });
}

// El total va en la unidad del insumo; medida, ancho y alto, en mm (`db_schema/catalogo.md` → *El despiece*).
export function textoFila(f: FilaDespiece): string {
  const corte =
    f.ancho !== undefined && f.alto !== undefined
      ? `${textoMedida(f.ancho)} × ${textoMedida(f.alto)} mm`
      : f.medida !== undefined
        ? `${textoMedida(f.medida)} mm`
        : null;
  return [corte && `${corte} × ${textoMedida(f.cantidad)}`, `${textoMedida(f.total)} ${UNIDAD[f.unidad]}`]
    .filter(Boolean)
    .join(" = ");
}
