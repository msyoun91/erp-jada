"use client";

import { useMemo, useState } from "react";
import type { TareaHilo } from "../types";
import { HILO_ESTADO_BADGE, HILO_ESTADO_LABEL } from "./estado";

export function HiloBuscador({
  hilos,
  value,
  onChange,
}: {
  hilos: TareaHilo[];
  value: string;
  onChange: (hiloId: string) => void;
}) {
  const [busqueda, setBusqueda] = useState("");

  const seleccionado = hilos.find((h) => h.id === value);

  const filtrados = useMemo(() => {
    const q = busqueda.trim().toLowerCase();
    if (!q) return [];
    return hilos.filter((h) => h.titulo.toLowerCase().includes(q));
  }, [hilos, busqueda]);

  if (seleccionado) {
    return (
      <div className="flex items-center justify-between rounded-md border-[1.5px] border-border-strong bg-bg-surface px-3 py-[9px]">
        <span className="text-sm text-text-primary">{seleccionado.titulo}</span>
        <button type="button" className="t-caption text-text-brand" onClick={() => onChange("")}>
          Cambiar
        </button>
      </div>
    );
  }

  return (
    <div>
      <input
        className="input"
        placeholder="Buscar hilo por título..."
        value={busqueda}
        onChange={(e) => setBusqueda(e.target.value)}
      />
      {busqueda.trim() !== "" && (
        <div className="mt-1 max-h-40 overflow-y-auto rounded-md border border-border">
          {filtrados.length === 0 ? (
            <p className="t-caption px-3 py-2">Sin resultados.</p>
          ) : (
            filtrados.map((h) => (
              <button
                key={h.id}
                type="button"
                onClick={() => onChange(h.id)}
                className="flex w-full items-center justify-between px-3 py-2 text-left text-sm text-text-primary hover:bg-bg-subtle"
              >
                {h.titulo}
                <span className={`badge ${HILO_ESTADO_BADGE[h.estado]}`}>{HILO_ESTADO_LABEL[h.estado]}</span>
              </button>
            ))
          )}
        </div>
      )}
    </div>
  );
}
