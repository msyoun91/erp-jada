"use client";

import { AlertTriangle } from "lucide-react";

// El sistema avisa, no bloquea: los únicos duplicados imposibles son los que
// tienen constraint (CUIT, email). Para el resto la decisión es de quien carga
// — dos obras pueden llamarse igual en localidades distintas.
export function AvisoDuplicados({ items }: { items: string[] }) {
  if (items.length === 0) return null;

  return (
    <div className="rounded-md border border-warning-text/30 bg-warning-bg p-3">
      <p className="t-body-m flex items-center gap-1.5 font-semibold text-warning-text">
        <AlertTriangle size={14} strokeWidth={1.75} className="shrink-0" />
        Ya existe algo parecido
      </p>
      <ul className="mt-1 list-disc pl-5">
        {items.map((item) => (
          <li key={item} className="t-caption">
            {item}
          </li>
        ))}
      </ul>
      <p className="t-caption mt-1">Revisá antes de crear un registro nuevo.</p>
    </div>
  );
}
