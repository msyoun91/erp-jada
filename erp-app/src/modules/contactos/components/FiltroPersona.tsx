"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { UserRound } from "lucide-react";
import { SearchInput } from "@/components/ui/SearchInput";
import { buscarAuditadas } from "../actions";
import { useBusqueda } from "./useBusqueda";

// "¿Quién miró a Marta?": busca solo entre personas con algún acceso.
export function FiltroPersona({ base }: { base: string }) {
  const router = useRouter();
  const [abierto, setAbierto] = useState(false);
  const [texto, setTexto] = useState("");
  const { buscable, resultados } = useBusqueda(texto, buscarAuditadas);

  if (!abierto) {
    return (
      <button type="button" className="btn btn-secondary btn-sm" onClick={() => setAbierto(true)}>
        <UserRound size={14} strokeWidth={1.75} />
        Filtrar por persona
      </button>
    );
  }

  return (
    <div className="relative w-full sm:w-72">
      <SearchInput value={texto} onChange={setTexto} placeholder="Buscar persona" autoFocus />
      {buscable && (
        <ul className="absolute z-10 mt-1 flex w-full flex-col rounded-lg border border-border bg-bg-surface shadow-md">
          {resultados === null && <li className="t-caption px-3 py-2 text-text-tertiary">Buscando…</li>}
          {resultados?.length === 0 && <li className="t-caption px-3 py-2 text-text-tertiary">Nadie la miró.</li>}
          {resultados?.map((r) => (
            <li key={r.id}>
              <button
                type="button"
                onClick={() => router.push(`${base}${base.includes("?") ? "&" : "?"}persona=${r.id}`)}
                className="tap-target t-body-m w-full truncate px-3 py-2 text-left hover:bg-bg-subtle"
              >
                {r.nombre}
              </button>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
