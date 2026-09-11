"use client";

import { useState } from "react";
import { Plus, X } from "lucide-react";
import { SearchInput } from "@/components/ui/SearchInput";
import type { Usuario } from "../types";

// Con un equipo de más de un puñado, la lista de checkboxes obligaba a
// scrollear para encontrar a alguien: se busca y se agrega. Las sugerencias
// quedan acotadas y visibles sin foco — no hay popover que abrir ni cerrar.
const MAX_SUGERENCIAS = 6;

export function SelectorUsuarios({
  opciones,
  seleccionados,
  onChange,
  nombreDe,
  sinOpciones,
}: {
  opciones: Usuario[];
  seleccionados: string[];
  onChange: (ids: string[]) => void;
  nombreDe: (id: string) => string;
  sinOpciones: string;
}) {
  const [texto, setTexto] = useState("");
  const q = texto.trim().toLowerCase();
  const sugerencias = opciones
    .filter((u) => !seleccionados.includes(u.id) && u.nombre.toLowerCase().includes(q))
    .slice(0, MAX_SUGERENCIAS);

  function agregar(id: string) {
    onChange([...seleccionados, id]);
    setTexto("");
  }

  return (
    <div>
      {seleccionados.length > 0 && (
        <div className="mb-2 flex flex-wrap gap-1.5">
          {seleccionados.map((id) => (
            <span
              key={id}
              className="t-caption inline-flex items-center gap-0.5 rounded-full bg-brand-50 py-0.5 pl-3 pr-0.5 font-medium text-brand-700"
            >
              {nombreDe(id)}
              <button
                type="button"
                className="tap-target flex items-center rounded-full p-1.5 hover:bg-bg-subtle"
                aria-label={`Quitar a ${nombreDe(id)}`}
                onClick={() => onChange(seleccionados.filter((x) => x !== id))}
              >
                <X size={12} strokeWidth={2} />
              </button>
            </span>
          ))}
        </div>
      )}

      {/* Enter agrega la primera coincidencia en vez de mandar el formulario;
          con el buscador vacío no agrega a nadie. */}
      <div
        onKeyDown={(e) => {
          if (e.key !== "Enter") return;
          e.preventDefault();
          if (q && sugerencias[0]) agregar(sugerencias[0].id);
        }}
      >
        <SearchInput value={texto} onChange={setTexto} placeholder="Buscar para agregar…" />
      </div>

      {sugerencias.length > 0 ? (
        <div className="mt-1 flex flex-col rounded-md border border-border">
          {sugerencias.map((u) => (
            <button
              key={u.id}
              type="button"
              className="tap-target t-body-m flex items-center gap-2 px-3 py-2 text-left hover:bg-bg-subtle"
              onClick={() => agregar(u.id)}
            >
              <Plus size={14} strokeWidth={1.75} className="shrink-0 text-text-tertiary" />
              {u.nombre}
            </button>
          ))}
        </div>
      ) : (
        <p className="t-caption mt-1">
          {q
            ? `Nadie más coincide con “${texto.trim()}”.`
            : opciones.length === 0
              ? sinOpciones
              : "Ya están todos agregados."}
        </p>
      )}
    </div>
  );
}
