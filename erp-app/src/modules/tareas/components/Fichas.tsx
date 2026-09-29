"use client";

import { ArrowLeft } from "lucide-react";

// Una ficha al lado del paso: `ref` es `ente:id`, como en `enlaces`.
export type Pestana = { ref: string; etiqueta: string; ficha: React.ReactNode };

// Las fichas del paso en pestañas. En mobile van encima del paso: `onVolver` vuelve a él.
export function Fichas({
  pestanas,
  activa,
  onActiva,
  onVolver,
  className,
}: {
  pestanas: Pestana[];
  activa: string | null;
  onActiva: (ref: string) => void;
  onVolver: () => void;
  className: string;
}) {
  const actual = pestanas.find((p) => p.ref === activa) ?? pestanas[0];
  if (!actual) return null;

  return (
    <div className={`min-w-0 flex-1 flex-col ${className}`}>
      <div role="tablist" className="flex shrink-0 items-center gap-4 overflow-x-auto border-b border-border px-5 pt-3">
        <button className="btn btn-ghost btn-sm mb-1 lg:hidden" onClick={onVolver}>
          <ArrowLeft size={14} />
          Paso
        </button>
        {pestanas.map((p) => (
          <button
            key={p.ref}
            role="tab"
            aria-selected={p.ref === actual.ref}
            onClick={() => onActiva(p.ref)}
            className={`t-body-m shrink-0 px-1 pb-2 font-medium ${
              p.ref === actual.ref ? "border-b-2 border-brand-500 text-text-brand" : "text-text-tertiary"
            }`}
          >
            {p.etiqueta}
          </button>
        ))}
      </div>
      {pestanas.map((p) => (
        <div key={p.ref} role="tabpanel" aria-label={p.etiqueta} hidden={p.ref !== actual.ref} className="min-h-0 flex-1 overflow-y-auto p-5">
          {p.ficha}
        </div>
      ))}
    </div>
  );
}

// El lugar de las fichas mientras el servidor las arma (`esperaFichas`).
export function FichasCargando({ className }: { className: string }) {
  return (
    <div role="status" aria-label="Cargando fichas" className={`min-w-0 flex-1 items-center justify-center ${className}`}>
      <span className="h-8 w-8 animate-spin rounded-full border-[3px] border-border border-t-brand-500" />
    </div>
  );
}

// En mobile, un botón por ficha debajo del paso.
export function BotonesFichas({ pestanas, onFicha }: { pestanas: Pestana[]; onFicha: (ref: string) => void }) {
  if (pestanas.length === 0) return null;
  return (
    <div className="flex flex-wrap gap-2 lg:hidden">
      {pestanas.map((p) => (
        <button key={p.ref} className="btn btn-secondary btn-sm" onClick={() => onFicha(p.ref)}>
          {p.etiqueta}
        </button>
      ))}
    </div>
  );
}
