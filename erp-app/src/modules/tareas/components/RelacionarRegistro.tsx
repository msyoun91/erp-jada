"use client";

import { useEffect, useState } from "react";
import { SearchInput } from "@/components/ui/SearchInput";
import { ENTES } from "@/lib/entes";
import { buscarRegistros } from "../actions";
import type { RegistroElegido } from "../types";

// El mismo piso que `obras_buscar`.
const MINIMO = 2;

// Buscador de "Relacionar": obras, empresas y personas que quien busca puede
// abrir (`buscar_registros`, sql/059). Los resultados van en línea y no en un
// popover porque vive adentro de un panel. Enter elige el primero en vez de
// mandar el form, como `SelectorUsuarios`.
export function RelacionarRegistro({
  yaElegidos,
  onElegir,
}: {
  yaElegidos: { ente: string; registro_id: string }[];
  onElegir: (r: RegistroElegido) => void;
}) {
  const [texto, setTexto] = useState("");
  const [resultados, setResultados] = useState<RegistroElegido[]>([]);
  const [buscando, setBuscando] = useState(false);
  const consulta = texto.trim();

  // Mismo patrón que el BuscadorGlobal de Obras: debounce, y el estado se toca
  // adentro del timeout y de la promesa, nunca en el cuerpo del efecto.
  useEffect(() => {
    if (consulta.length < MINIMO) return;

    let vigente = true;
    const timer = setTimeout(() => {
      setBuscando(true);
      buscarRegistros(consulta).then((r) => {
        if (!vigente) return;
        setResultados(r);
        setBuscando(false);
      });
    }, 250);

    return () => {
      vigente = false;
      clearTimeout(timer);
    };
  }, [consulta]);

  const disponibles = resultados.filter(
    (r) => !yaElegidos.some((e) => e.ente === r.ente && e.registro_id === r.registro_id),
  );

  function elegir(r: RegistroElegido) {
    onElegir(r);
    setTexto("");
    setResultados([]);
  }

  return (
    <div
      onKeyDown={(e) => {
        if (e.key !== "Enter") return;
        e.preventDefault();
        if (disponibles[0]) elegir(disponibles[0]);
      }}
    >
      <div className="flex">
        <SearchInput value={texto} onChange={setTexto} placeholder="Buscar obra, empresa o persona…" />
      </div>
      {consulta.length >= MINIMO && (
        <ul className="mt-1 flex flex-col" aria-live="polite">
          {disponibles.length === 0 ? (
            <li className="t-caption px-2 py-1">{buscando ? "Buscando…" : "Nada que puedas abrir con ese nombre."}</li>
          ) : (
            disponibles.map((r) => (
              <li key={`${r.ente}-${r.registro_id}`}>
                <button
                  type="button"
                  className="tap-target flex w-full min-w-0 items-baseline gap-2 rounded-md px-2 py-1 text-left hover:bg-bg-subtle"
                  onClick={() => elegir(r)}
                >
                  <span className="t-caption shrink-0">{ENTES[r.ente]?.nombre ?? r.ente}</span>
                  <span className="t-body-m truncate">{r.etiqueta}</span>
                  {r.detalle && <span className="t-caption truncate">{r.detalle}</span>}
                </button>
              </li>
            ))
          )}
        </ul>
      )}
    </div>
  );
}
