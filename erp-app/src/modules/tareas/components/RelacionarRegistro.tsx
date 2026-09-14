"use client";

import { useEffect, useState } from "react";
import { Link2 } from "lucide-react";
import { SearchInput } from "@/components/ui/SearchInput";
import { LABEL_MAP } from "@/components/layout/SidebarNav";
import { ENTES } from "@/lib/entes";
import { buscarRegistros, modulosRelacionables } from "../actions";
import { Segmentado } from "./Segmentado";
import type { RegistroElegido } from "../types";

// El mismo piso que `obras_buscar`.
const MINIMO = 2;

function labelModulo(modulo: string) {
  return LABEL_MAP[modulo] ?? modulo[0].toUpperCase() + modulo.slice(1);
}

// Toggle de "Relacionar" (sql/061): primero se elige el módulo, recién ahí
// aparece el buscador — sin módulo elegido no hay buscador ni resultados.
// Usado tanto en el form de creación como en el panel de la tarea: una sola
// fuente para las dos superficies.
export function RelacionarRegistro({
  yaElegidos,
  onElegir,
}: {
  yaElegidos: { ente: string; registro_id: string }[];
  onElegir: (r: RegistroElegido) => void;
}) {
  const [abierto, setAbierto] = useState(false);
  const [modulos, setModulos] = useState<string[] | null>(null);
  const [modulo, setModulo] = useState("");
  const [texto, setTexto] = useState("");
  const [resultados, setResultados] = useState<RegistroElegido[]>([]);
  const [buscando, setBuscando] = useState(false);
  const consulta = texto.trim();

  function abrir() {
    setAbierto(true);
    if (modulos === null) modulosRelacionables().then(setModulos);
  }

  function cerrar() {
    setAbierto(false);
    setModulo("");
    setTexto("");
    setResultados([]);
  }

  function elegirModulo(m: string) {
    setModulo(m);
    setTexto("");
    setResultados([]);
  }

  // Mismo patrón que el BuscadorGlobal de Obras: debounce, y el estado se toca
  // adentro del timeout y de la promesa, nunca en el cuerpo del efecto.
  useEffect(() => {
    if (!modulo || consulta.length < MINIMO) return;

    let vigente = true;
    const timer = setTimeout(() => {
      setBuscando(true);
      buscarRegistros(modulo, consulta).then((r) => {
        if (!vigente) return;
        setResultados(r);
        setBuscando(false);
      });
    }, 250);

    return () => {
      vigente = false;
      clearTimeout(timer);
    };
  }, [modulo, consulta]);

  const disponibles = resultados.filter(
    (r) => !yaElegidos.some((e) => e.ente === r.ente && e.registro_id === r.registro_id),
  );

  function elegir(r: RegistroElegido) {
    onElegir(r);
    cerrar();
  }

  return (
    <div>
      <button
        type="button"
        className="tap-target t-caption flex items-center gap-1 font-semibold text-brand-700"
        onClick={() => (abierto ? cerrar() : abrir())}
      >
        <Link2 size={13} strokeWidth={1.75} />
        {abierto ? "Cerrar" : "Relacionar"}
      </button>

      {abierto && (
        <div className="mt-2 flex flex-col gap-2">
          {modulos === null ? (
            <p className="t-caption">Cargando módulos…</p>
          ) : modulos.length === 0 ? (
            <p className="t-caption">No tenés acceso a ningún módulo con registros para relacionar.</p>
          ) : (
            <Segmentado
              etiqueta="Módulo"
              opciones={modulos.map((m) => ({ valor: m, label: labelModulo(m) }))}
              valor={modulo}
              onChange={elegirModulo}
            />
          )}

          {modulo && (
            <div
              onKeyDown={(e) => {
                if (e.key !== "Enter") return;
                e.preventDefault();
                if (disponibles[0]) elegir(disponibles[0]);
              }}
            >
              <div className="flex">
                <SearchInput value={texto} onChange={setTexto} placeholder={`Buscar en ${labelModulo(modulo)}…`} />
              </div>
              {consulta.length >= MINIMO && (
                <ul className="mt-1 flex flex-col" aria-live="polite">
                  {disponibles.length === 0 ? (
                    <li className="t-caption px-2 py-1">
                      {buscando ? "Buscando…" : "Nada que puedas abrir con ese nombre."}
                    </li>
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
          )}
        </div>
      )}
    </div>
  );
}
