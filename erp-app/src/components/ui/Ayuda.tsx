"use client";

import { useId, useState } from "react";
import { CircleHelp } from "lucide-react";

// El "?" de un campo difícil: abre un ejemplo en el renglón de abajo. Inline y no popover: en un panel lateral
// no hay lugar al costado, y en touch no hay hover.
export function Ayuda({
  de,
  ejemplo,
  className = "",
  children,
}: {
  // Para el lector de pantalla: "Ver un ejemplo de <de>".
  de: string;
  ejemplo: React.ReactNode;
  className?: string;
  // Lo que lleva el "?" al lado: la etiqueta del campo, un checkbox, un título.
  children: React.ReactNode;
}) {
  const [abierta, setAbierta] = useState(false);
  const id = useId();

  return (
    <div className={className}>
      <div className="flex items-center gap-x-1">
        {children}
        <button
          type="button"
          className={`icon-btn -my-2 h-7 w-7 ${abierta ? "text-text-brand" : "text-text-tertiary"}`}
          aria-label={`Ver un ejemplo de ${de}`}
          aria-expanded={abierta}
          aria-controls={abierta ? id : undefined}
          onClick={() => setAbierta((a) => !a)}
        >
          <CircleHelp size={15} strokeWidth={1.75} />
        </button>
      </div>
      {abierta && (
        <div
          id={id}
          className="t-body-m mt-1 flex flex-col gap-1 rounded-md bg-info-bg p-3 text-info-text [&_code]:font-mono"
        >
          {ejemplo}
        </div>
      )}
    </div>
  );
}
