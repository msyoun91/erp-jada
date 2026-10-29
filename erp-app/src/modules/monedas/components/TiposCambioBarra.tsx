"use client";

import { useTransition } from "react";
import Link from "next/link";
import { RefreshCw, TriangleAlert } from "lucide-react";
import { toast } from "sonner";
import { MONEDAS, formatPesos } from "@/lib/monedas";
import { formatFecha } from "@/lib/utils";
import { actualizarTiposCambio } from "../actions";
import { textoAviso } from "../etiquetas";
import type { Aviso, TipoCambioHoy } from "../types";

// En la barra de menú de todo usuario (decisiones/monedas.md → Quién los ve). Los
// avisos llegan solo a quien puede corregir; el link, a quien ve el módulo.
export function TiposCambioBarra({
  hoy,
  avisos,
  puedeVer,
}: {
  hoy: TipoCambioHoy[];
  avisos: Aviso[];
  puedeVer: boolean;
}) {
  const [pendiente, startTransition] = useTransition();

  function actualizar() {
    startTransition(async () => {
      const r = await actualizarTiposCambio();
      if (!r.success) toast.error(r.error);
      else toast.success(r.reciente ? "Se actualizó hace menos de un minuto" : "Tipos de cambio actualizados");
    });
  }

  const titulo = <span className="t-caption font-semibold uppercase tracking-wide">Tipos de cambio</span>;

  return (
    <div className="mt-2 border-t border-border pt-2">
      <div className="flex items-center justify-between">
        {puedeVer ? (
          <Link href="/monedas" className="hover:underline">
            {titulo}
          </Link>
        ) : (
          titulo
        )}
        <button
          onClick={actualizar}
          disabled={pendiente}
          className="icon-btn text-text-tertiary hover:text-text-secondary"
          aria-label="Actualizar tipos de cambio"
          title="Actualizar tipos de cambio"
        >
          <RefreshCw size={14} strokeWidth={1.75} className={pendiente ? "animate-spin" : ""} />
        </button>
      </div>
      <ul className="flex flex-col gap-0.5">
        {hoy.map((t) => (
          <li key={t.moneda} className="t-caption flex items-baseline justify-between gap-2">
            <span>{MONEDAS[t.moneda]}</span>
            <span>
              <span className="font-semibold text-text-primary">{t.valor === null ? "—" : formatPesos(t.valor)}</span>
              {t.fecha && <span className="ml-1 text-text-tertiary">{formatFecha(t.fecha)}</span>}
            </span>
          </li>
        ))}
      </ul>
      {avisos.map((a) => (
        <Link
          key={`${a.aviso}-${a.moneda ?? ""}`}
          href="/monedas"
          className="t-caption mt-1 flex items-start gap-1 text-warning-text hover:underline"
        >
          <TriangleAlert size={12} strokeWidth={1.75} className="mt-0.5 shrink-0" />
          {textoAviso(a)}
        </Link>
      ))}
    </div>
  );
}
