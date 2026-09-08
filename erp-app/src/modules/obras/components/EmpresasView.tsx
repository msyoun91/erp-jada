"use client";

import { useState } from "react";
import Link from "next/link";
import { Briefcase, Plus } from "lucide-react";
import { Paginacion, usePaginado } from "@/components/ui/Paginacion";
import { SearchInput } from "@/components/ui/SearchInput";
import type { Empresa } from "../types";
import { EmpresaFormPanel } from "./EmpresaFormPanel";

export function EmpresasView({
  empresas,
  puedeCrear,
}: {
  empresas: Empresa[];
  puedeCrear: boolean;
}) {
  const [texto, setTexto] = useState("");
  const [creando, setCreando] = useState(false);

  const q = texto.trim().toLowerCase();
  const filtradas = empresas.filter(
    (e) =>
      !q ||
      e.razon_social.toLowerCase().includes(q) ||
      (e.nombre_comercial ?? "").toLowerCase().includes(q),
  );
  const { visibles, ...paginado } = usePaginado(filtradas);

  return (
    <div>
      <div className="mb-4 flex flex-wrap items-center gap-3">
        <SearchInput value={texto} onChange={setTexto} placeholder="Buscar empresa…" />
        {puedeCrear && (
          <button className="btn btn-primary" onClick={() => setCreando(true)}>
            <Plus size={16} />
            Nueva empresa
          </button>
        )}
      </div>

      <Paginacion {...paginado} etiqueta="empresas" />

      {filtradas.length === 0 ? (
        <div className="card flex flex-col items-center gap-2 p-8 text-center">
          <Briefcase size={32} strokeWidth={1.5} className="text-text-tertiary" />
          <p className="t-body-m">
            {empresas.length === 0
              ? "Todavía no hay empresas cargadas."
              : "Ninguna empresa coincide con la búsqueda."}
          </p>
        </div>
      ) : (
        <ul className="flex flex-col gap-2">
          {visibles.map((e) => (
            <li key={e.id}>
              <Link
                href={`/obras/empresas/${e.id}`}
                className="card flex min-h-[44px] flex-wrap items-center gap-x-3 gap-y-1 p-3 hover:bg-bg-subtle"
              >
                <span className="t-body-m min-w-0 flex-1 truncate font-semibold">
                  {e.razon_social}
                </span>
                {e.pendiente && <span className="badge badge-warning">Pendiente</span>}
                {e.nombre_comercial && <span className="t-caption">{e.nombre_comercial}</span>}
                {e.localidad && <span className="t-caption">{e.localidad}</span>}
                {e.telefono && <span className="t-caption">{e.telefono}</span>}
              </Link>
            </li>
          ))}
        </ul>
      )}

      {creando && <EmpresaFormPanel onClose={() => setCreando(false)} />}
    </div>
  );
}
