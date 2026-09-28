"use client";

import { useState } from "react";
import Link from "next/link";
import { TriangleAlert } from "lucide-react";
import { toast } from "sonner";
import { buscarParecidas } from "../actions";
import type { Coincide, ParecidaAviso, ParecidasForm } from "../types";
import type { TipoContacto } from "./Buscador";

export const COINCIDE: Record<Coincide, string> = {
  nombre: "nombre parecido",
  telefono: "mismo teléfono",
  email: "mismo email",
};

// Aviso a ciegas antes de guardar: la primera vez que hay parecidas, las
// muestra y frena; el segundo intento con los mismos datos pasa, y la base la
// congela.
export function useParecidas() {
  const [aviso, setAviso] = useState<{ clave: string; items: ParecidaAviso[] } | null>(null);

  async function revisar(datos: ParecidasForm) {
    const clave = JSON.stringify(datos);
    if (aviso?.clave === clave) return true;
    const r = await buscarParecidas(datos);
    if (!r.success) {
      toast.error(r.error);
      return false;
    }
    if (r.resultados.length === 0) return true;
    setAviso({ clave, items: r.resultados });
    return false;
  }

  return { parecidas: aviso?.items ?? null, revisar };
}

// Estable: un ref inline corre en cada render y movería el scroll al tipear.
function alAparecer(el: HTMLDivElement | null) {
  el?.scrollIntoView({ block: "nearest" });
}

// Tuya (trae qué coincidió): entera, con "Vincular esa" si hay `onUsar`; de
// otro, nombre, dueño y, de una empresa, su equipo, así se la pide.
export function AvisoParecidas({
  tipo,
  items,
  verbo,
  onUsar,
  usar = "Vincular esa",
}: {
  tipo: TipoContacto;
  items: ParecidaAviso[];
  verbo: string;
  onUsar?: (p: ParecidaAviso & { id: string }) => void;
  usar?: string;
}) {
  const ruta = tipo === "persona" ? "personas" : "empresas";
  const una = tipo === "persona" ? "otra persona" : "otra empresa";
  const varias = tipo === "persona" ? "otras personas" : "otras empresas";
  return (
    <div
      ref={alAparecer}
      className="rounded-md border border-warning/20 bg-warning-bg px-3 py-2 text-warning-text"
    >
      <p className="t-body-m flex items-center gap-2 font-medium">
        <TriangleAlert size={16} strokeWidth={1.75} className="shrink-0" />
        Se parece a {items.length === 1 ? una : varias}
      </p>
      <ul className="t-body-m mt-1 flex flex-col gap-1">
        {items.map((p, i) =>
          p.coincide ? (
            <li key={p.id ?? i} className="flex flex-wrap items-center gap-x-2">
              <span>
                Ya la tenés:{" "}
                {p.id ? (
                  <Link href={`/contactos/${ruta}/${p.id}`} target="_blank" className="underline">
                    {p.nombre}
                  </Link>
                ) : (
                  `${p.nombre} (espera aprobación)`
                )}{" "}
                · {p.coincide.map((c) => COINCIDE[c]).join(", ")}
              </span>
              {onUsar && p.id && (
                <button type="button" className="btn btn-secondary btn-sm" onClick={() => onUsar({ ...p, id: p.id as string })}>
                  {usar}
                </button>
              )}
            </li>
          ) : (
            <li key={p.id ?? i}>
              {p.nombre}, de {p.dueno}
              {p.equipo && ` (${p.equipo})`}
            </li>
          )
        )}
      </ul>
      <p className="t-caption mt-1">Si es otra, {verbo} igual: queda por aprobar hasta que la revisen.</p>
    </div>
  );
}

// En la ficha de una congelada: lo que la base frena hasta que la aprueben (CO020).
export function EsperaAprobacion({ tipo }: { tipo: TipoContacto }) {
  return (
    <p className="t-body-m flex items-start gap-2 rounded-md border border-warning/20 bg-warning-bg px-3 py-2 text-warning-text">
      <TriangleAlert size={16} strokeWidth={1.75} className="mt-0.5 shrink-0" />
      {tipo === "persona"
        ? "Se parece a otra persona y espera aprobación. Mientras tanto no se transfiere ni se vincula."
        : "Se parece a otra empresa y espera aprobación. Mientras tanto no se vincula."}
    </p>
  );
}
