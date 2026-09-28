import Link from "next/link";
import { FiltroDias } from "@/components/ui/FiltroDias";
import { WidgetCard } from "@/components/ui/WidgetCard";
import { MOTIVO, ORIGEN, TIPO } from "../etiquetas";
import type { Numero } from "../queries";
import { LABEL_ESTADO, type EstadoObra } from "../types";

type Fila = { clave: string; label: string; cantidad: number };

function filas(numeros: Numero[], grupo: string, label: (clave: string) => string): Fila[] {
  return numeros
    .filter((n) => n.grupo === grupo && n.cantidad > 0)
    .map((n) => ({ clave: n.clave, label: label(n.clave), cantidad: n.cantidad }))
    .sort((a, b) => b.cantidad - a.cantidad);
}

// Una barra por clave, relativa al máximo del grupo; el número al lado.
function Barras({ titulo, filas }: { titulo: string; filas: Fila[] }) {
  const max = Math.max(1, ...filas.map((f) => f.cantidad));
  return (
    <div className="min-w-0">
      <p className="t-caption mb-1">{titulo}</p>
      <ul className="flex flex-col gap-1">
        {filas.map((f) => (
          <li key={f.clave} className="grid grid-cols-[minmax(0,9rem)_1fr] items-center gap-2" title={`${f.label}: ${f.cantidad}`}>
            <span className="t-body-m truncate">{f.label}</span>
            <span className="flex items-center gap-2">
              <span className="h-2 rounded-sm bg-brand-500" style={{ width: `${(f.cantidad / max) * 100}%` }} />
              <span className="t-body-m tabular-nums text-text-secondary">{f.cantidad}</span>
            </span>
          </li>
        ))}
      </ul>
    </div>
  );
}

function total(filas: Fila[]) {
  return filas.reduce((s, f) => s + f.cantidad, 0);
}

// Arriba, cómo están hoy; abajo, lo que se contrató y se perdió en el período
// (`decisiones/obras.md` → *El período del widget*). Solo cantidades.
export function WidgetObras({ numeros, dias, columnas }: { numeros: Numero[]; dias: number; columnas: 1 | 2 }) {
  const hoy = new Map(numeros.filter((n) => n.grupo === "estado").map((n) => [n.clave, n.cantidad]));
  const origen = filas(numeros, "origen", (c) => ORIGEN[c as keyof typeof ORIGEN] ?? c);
  const tipo = filas(numeros, "tipo", (c) => TIPO[c as keyof typeof TIPO] ?? c);
  const motivo = filas(numeros, "motivo", (c) => MOTIVO[c as keyof typeof MOTIVO]?.label ?? c);
  const contratadas = total(origen);
  const perdidas = total(motivo);

  return (
    <WidgetCard
      titulo="Obras"
      icono="obras"
      columnas={columnas}
      accion={<FiltroDias href="/" dias={dias} etiqueta="Período de las obras" />}
    >
      <div className="flex flex-wrap items-baseline gap-x-4 gap-y-1">
        <span className="t-caption">Hoy</span>
        {(Object.keys(LABEL_ESTADO) as EstadoObra[]).map((e) => (
          <Link key={e} href="/obras" className="t-body-m hover:underline">
            {LABEL_ESTADO[e].label} <span className="font-semibold tabular-nums">{hoy.get(e) ?? 0}</span>
          </Link>
        ))}
      </div>

      <div className="mt-4 flex flex-col gap-4 border-t border-border pt-3">
        <div>
          <p className="t-body-m mb-2">
            Contratadas en {dias} días: <span className="font-semibold tabular-nums">{contratadas}</span>
          </p>
          {contratadas > 0 && (
            <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
              <Barras titulo="Por origen" filas={origen} />
              <Barras titulo="Por tipo" filas={tipo} />
            </div>
          )}
        </div>
        <div>
          <p className="t-body-m mb-2">
            Perdidas en {dias} días: <span className="font-semibold tabular-nums">{perdidas}</span>
          </p>
          {perdidas > 0 && (
            <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
              <Barras titulo="Por motivo" filas={motivo} />
            </div>
          )}
        </div>
      </div>
    </WidgetCard>
  );
}
