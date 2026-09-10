"use client";

import { useEffect, useRef, useState } from "react";
import Link from "next/link";
import { Briefcase, Building2, UserRound, type LucideIcon } from "lucide-react";
import { SearchInput } from "@/components/ui/SearchInput";
import { buscarGlobal } from "../actions";
import { LABEL_TIPO_RESULTADO, TIPOS_RESULTADO } from "../types";
import type { ResultadoBusqueda, TipoResultado } from "../types";

// El mismo piso que `obras_buscar`. Está en los dos lados por lo mismo que los
// schemas de Zod: acá evita el viaje, en la base es la regla.
const MINIMO = 2;

const ICONO: Record<TipoResultado, LucideIcon> = {
  obra: Building2,
  empresa: Briefcase,
  persona: UserRound,
};

const RUTA: Record<TipoResultado, (id: string) => string> = {
  obra: (id) => `/obras/${id}`,
  empresa: (id) => `/obras/empresas/${id}`,
  persona: (id) => `/obras/personas/${id}`,
};

// Una barra para las tres entidades, arriba de las tabs porque su efecto llega
// más lejos que la tab abierta.
//
// Vive en el layout del módulo, así que sobrevive a la navegación: al elegir un
// resultado se limpia sola.
export function BuscadorGlobal() {
  const [texto, setTexto] = useState("");
  const [resultados, setResultados] = useState<ResultadoBusqueda[]>([]);
  const [buscando, setBuscando] = useState(false);
  const [cerrado, setCerrado] = useState(false);
  const caja = useRef<HTMLDivElement>(null);

  const consulta = texto.trim();
  const abierto = !cerrado && consulta.length >= MINIMO;

  // Sin debounce el buscador dispara una consulta por tecla. El estado se toca
  // adentro del timeout y del callback de la promesa, nunca en el cuerpo del
  // efecto — el lint del repo corta el setState síncrono acá.
  useEffect(() => {
    if (consulta.length < MINIMO) return;

    let vigente = true;
    const timer = setTimeout(() => {
      setBuscando(true);
      buscarGlobal(consulta).then((r) => {
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

  // Click afuera: el panel flota sobre el contenido y no puede quedarse abierto
  // tapándolo. `mousedown` y no `blur`, que dispara antes del click en un
  // resultado y se lo comería.
  useEffect(() => {
    function afuera(e: MouseEvent) {
      if (!caja.current?.contains(e.target as Node)) setCerrado(true);
    }

    document.addEventListener("mousedown", afuera);
    return () => document.removeEventListener("mousedown", afuera);
  }, []);

  function elegir() {
    setTexto("");
    setResultados([]);
  }

  return (
    <div
      ref={caja}
      className="relative w-full md:w-96"
      onKeyDown={(e) => e.key === "Escape" && setCerrado(true)}
    >
      <div className="flex">
        <SearchInput
          value={texto}
          onChange={(v) => {
            setTexto(v);
            setCerrado(false);
          }}
          placeholder="Buscar obra, empresa o persona…"
        />
      </div>

      {abierto && (
        <div
          className="card absolute inset-x-0 top-full z-20 mt-1 max-h-[70vh] overflow-y-auto p-2 shadow-md"
          aria-live="polite"
        >
          {resultados.length === 0 ? (
            <p className="t-caption p-2">
              {buscando ? "Buscando…" : "No hay resultados para esa búsqueda."}
            </p>
          ) : (
            <>
              {TIPOS_RESULTADO.map((tipo) => {
                const grupo = resultados.filter((r) => r.tipo === tipo);
                if (grupo.length === 0) return null;

                return (
                  <section key={tipo}>
                    <p className="t-caption px-2 pb-1 pt-2 font-semibold">
                      {LABEL_TIPO_RESULTADO[tipo]}
                    </p>
                    <ul className="flex flex-col gap-1">
                      {grupo.map((r, i) => (
                        <li key={`${r.tipo}-${r.id ?? `ajeno-${i}`}`}>
                          <Fila resultado={r} onElegir={elegir} />
                        </li>
                      ))}
                    </ul>
                  </section>
                );
              })}
              <p className="t-caption px-2 pb-1 pt-3">
                Mostramos los primeros de cada tipo. Si no está, afiná la búsqueda.
              </p>
            </>
          )}
        </div>
      )}
    </div>
  );
}

// La persona fuera de alcance se lista pero no se abre: identidad mínima y el
// nombre de quien la cargó, para ir a pedirle el contacto. Abrirle la ficha es
// lo que `obras_ficha_persona()` registra, y esto no es eso.
function Fila({
  resultado,
  onElegir,
}: {
  resultado: ResultadoBusqueda;
  onElegir: () => void;
}) {
  const Icono = ICONO[resultado.tipo];

  const contenido = (
    <>
      <Icono size={16} strokeWidth={1.75} className="shrink-0 text-text-tertiary" />
      <span className="min-w-0 flex-1">
        <span
          className={`t-body-m block truncate ${
            resultado.es_ajeno ? "text-text-tertiary" : "font-semibold text-text-primary"
          }`}
        >
          {resultado.titulo}
        </span>
        {(resultado.subtitulo || resultado.duenio) && (
          <span className="t-caption block truncate">
            {[
              resultado.subtitulo,
              resultado.es_ajeno && resultado.duenio && `la cargó ${resultado.duenio}`,
            ]
              .filter(Boolean)
              .join(" · ")}
          </span>
        )}
      </span>
      {resultado.es_ajeno && <span className="badge badge-neutral shrink-0">Ajeno</span>}
    </>
  );

  if (resultado.es_ajeno || !resultado.id) {
    return <div className="tap-target flex items-center gap-2.5 p-2">{contenido}</div>;
  }

  return (
    <Link
      href={RUTA[resultado.tipo](resultado.id)}
      onClick={onElegir}
      className="tap-target flex items-center gap-2.5 rounded-md p-2 hover:bg-bg-subtle"
    >
      {contenido}
    </Link>
  );
}
