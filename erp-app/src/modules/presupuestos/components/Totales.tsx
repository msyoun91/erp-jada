import { formatMonto, MONEDAS } from "@/lib/monedas";
import type { VersionEditor } from "../queries";
import { formatAlicuota } from "../types";

// El pie de una versión, una columna por moneda: lo mismo en el editor y en el impreso.
export function Totales({
  totales,
  importes,
  conIva,
  descuento: porcentaje,
}: {
  totales: VersionEditor["totales"];
  importes: VersionEditor["importes"];
  conIva: boolean;
  descuento: number;
}) {
  return (
    <div className="flex flex-col gap-4">
      {totales.map((t) => {
        // Con IVA incluido, el descuento es subtotal − total: absorbe el redondeo y el total es el mismo (*Pantallas*).
        const subtotal = conIva
          ? importes.filter((i) => i.moneda === t.moneda).reduce((s, i) => s + (i.importe_con_iva ?? 0), 0)
          : t.subtotal;
        const descuento = conIva ? subtotal - t.total : t.descuento;
        return (
          <div key={t.moneda} className="flex flex-col gap-1">
            {totales.length > 1 && <p className="t-label">{MONEDAS[t.moneda]}</p>}
            <Linea texto="Subtotal" valor={formatMonto(subtotal, t.moneda)} />
            {descuento !== 0 && (
              <Linea texto={`Descuento ${formatAlicuota(porcentaje)}`} valor={`− ${formatMonto(descuento, t.moneda)}`} />
            )}
            {!conIva &&
              t.iva
                .filter((x) => x.monto !== 0)
                .map((x) => (
                  <Linea key={x.alicuota} texto={`IVA ${formatAlicuota(x.alicuota)}`} valor={formatMonto(x.monto, t.moneda)} />
                ))}
            <Linea texto={conIva ? "Total con IVA" : "Total"} valor={formatMonto(t.total, t.moneda)} fuerte />
            {t.sin_precio > 0 && (
              <p className="alert alert-warning mt-1">
                {t.sin_precio === 1 ? "1 importe sin precio no suma." : `${t.sin_precio} importes sin precio no suman.`}
              </p>
            )}
          </div>
        );
      })}
    </div>
  );
}

function Linea({ texto, valor, fuerte }: { texto: string; valor: string; fuerte?: boolean }) {
  return (
    <p className={`flex justify-between gap-3 ${fuerte ? "t-body-l font-semibold text-text-primary" : "t-body-m"}`}>
      <span>{texto}</span>
      <span className="tabular-nums">{valor}</span>
    </p>
  );
}
