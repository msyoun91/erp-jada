"use client";

import { useState } from "react";
import Link from "next/link";
import { Plus, UserRound } from "lucide-react";
import { Paginacion, usePaginado } from "@/components/ui/Paginacion";
import { SearchInput } from "@/components/ui/SearchInput";
import type { PersonaListado } from "../types";
import { AlcanceToggle } from "./AlcanceToggle";
import { PersonaFormPanel } from "./PersonaFormPanel";

export function PersonasView({
  personas,
  puedeCrear,
  veTodas,
}: {
  personas: PersonaListado[];
  puedeCrear: boolean;
  veTodas: boolean;
}) {
  const [texto, setTexto] = useState("");
  const [creando, setCreando] = useState(false);

  const q = texto.trim().toLowerCase();
  const filtradas = personas.filter(
    (p) => !q || `${p.nombre} ${p.apellido ?? ""}`.toLowerCase().includes(q),
  );
  const { visibles, ...paginado } = usePaginado(filtradas);

  return (
    <div>
      <div className="mb-4 flex flex-wrap items-center gap-3">
        <SearchInput value={texto} onChange={setTexto} placeholder="Buscar persona…" />
        {puedeCrear && (
          <button className="btn btn-primary" onClick={() => setCreando(true)}>
            <Plus size={16} />
            Nueva persona
          </button>
        )}
      </div>

      {veTodas ? (
        <div className="mb-3">
          <AlcanceToggle />
        </div>
      ) : (
        <p className="t-caption mb-2">
          Ves las personas que cargaste vos y las que te compartieron. Si buscás a alguien que no
          aparece, el formulario de alta te avisa si ya está cargada.
        </p>
      )}

      <Paginacion {...paginado} etiqueta="personas" />

      {filtradas.length === 0 ? (
        <div className="empty-state">
          <UserRound size={30} strokeWidth={1.5} className="mx-auto mb-3" />
          <p className="t-h3">
            {personas.length === 0 ? "Sin personas a tu alcance" : "Sin resultados"}
          </p>
          <p className="t-body-m mt-1">
            {personas.length === 0
              ? "Vas a ver las que cargues vos y las de tus obras."
              : "Probá con otro término de búsqueda."}
          </p>
        </div>
      ) : (
        <ul className="flex flex-col gap-2">
          {visibles.map((p) => (
            <li key={p.id}>
              {/* Sin teléfono ni email en el listado: el contacto sale por la
                  ficha, que registra el acceso. */}
              <Link
                href={`/obras/personas/${p.id}`}
                className="card card-link tap-target flex flex-wrap items-center gap-x-3 gap-y-1 p-3 hover:bg-bg-subtle"
              >
                <span className="t-body-m min-w-0 flex-1 truncate font-semibold">
                  {p.nombre} {p.apellido ?? ""}
                </span>
                {p.pendiente && <span className="badge badge-warning">Pendiente</span>}
              </Link>
            </li>
          ))}
        </ul>
      )}

      {creando && <PersonaFormPanel onClose={() => setCreando(false)} />}
    </div>
  );
}
