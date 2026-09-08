"use client";

import { useEffect, useState } from "react";
import { Search } from "lucide-react";

export type OpcionBuscador = { id: string; etiqueta: string; detalle?: string | null };

// Un solo buscador para todos los paneles de vinculación. Reemplaza a los
// `<select>` poblados con la lista entera: con la agenda creciendo, un
// desplegable de 400 empresas no es una forma de elegir, y en el caso de las
// personas además exponía la lista completa a quien solo tenía que vincular
// una.
//
// `buscar` tiene que ser estable entre renders (definila a nivel de módulo, no
// inline): el efecto de la primera carga la usa como dependencia.
export function Buscador({
  placeholder,
  buscar,
  onElegir,
  cargarAlAbrir = true,
  error,
}: {
  placeholder: string;
  buscar: (texto: string) => Promise<OpcionBuscador[]>;
  onElegir: (opcion: OpcionBuscador) => void;
  cargarAlAbrir?: boolean;
  error?: string;
}) {
  const [texto, setTexto] = useState("");
  const [resultados, setResultados] = useState<OpcionBuscador[]>([]);
  const [buscando, setBuscando] = useState(false);
  const [buscado, setBuscado] = useState(false);

  // Sin esto el panel abre en blanco y obliga a tipear para ver lo que antes
  // se veía solo. La búsqueda vacía trae las primeras y alcanza para elegir.
  useEffect(() => {
    if (!cargarAlAbrir) return;

    // El estado se toca en el callback y no en el cuerpo del efecto: el lint
    // del repo corta el setState síncrono acá, y con razón — encadena renders.
    let vigente = true;
    buscar("").then((r) => {
      if (!vigente) return;
      setResultados(r);
      // También marca `buscado`: si la primera carga vuelve vacía, el panel
      // tiene que decirlo en vez de quedarse mudo esperando que alguien tipee.
      setBuscado(true);
    });

    return () => {
      vigente = false;
    };
  }, [cargarAlAbrir, buscar]);

  async function correr() {
    setBuscando(true);
    setResultados(await buscar(texto));
    setBuscado(true);
    setBuscando(false);
  }

  return (
    <div>
      <div className="flex gap-2">
        <div className="relative min-w-[180px] flex-1">
          <Search
            size={14}
            strokeWidth={1.75}
            className="pointer-events-none absolute left-2.5 top-1/2 -translate-y-1/2 text-text-tertiary"
          />
          <input
            className={`input pl-8 ${error ? "input-error" : ""}`}
            placeholder={placeholder}
            aria-label={placeholder}
            value={texto}
            onChange={(e) => setTexto(e.target.value)}
            onKeyDown={(e) => e.key === "Enter" && (e.preventDefault(), correr())}
          />
        </div>
        {/* El label no cambia: mutarlo a "…" hacía saltar el ancho del botón
            justo cuando el usuario todavía lo tiene abajo del dedo. */}
        <button
          type="button"
          className="btn btn-secondary btn-sm"
          disabled={buscando}
          onClick={correr}
        >
          {buscando && (
            <span className="h-3.5 w-3.5 animate-spin rounded-full border-2 border-border border-t-brand-500" />
          )}
          Buscar
        </button>
      </div>

      {error && <p className="input-error-text">{error}</p>}

      {resultados.length > 0 && (
        <ul className="mt-2 flex flex-col gap-1">
          {resultados.map((o) => (
            <li key={o.id}>
              <button
                type="button"
                className="card card-link tap-target flex w-full flex-col justify-center gap-0.5 p-2 text-left hover:bg-bg-subtle"
                onClick={() => onElegir(o)}
              >
                <span className="t-body-m w-full truncate font-semibold text-text-primary">
                  {o.etiqueta}
                </span>
                {o.detalle && <span className="t-caption w-full truncate">{o.detalle}</span>}
              </button>
            </li>
          ))}
        </ul>
      )}

      {buscado && !buscando && resultados.length === 0 && (
        <p className="t-caption mt-2">No hay resultados para esa búsqueda.</p>
      )}
    </div>
  );
}
