"use client";

import { useState } from "react";
import Link from "next/link";
import { ChevronRight, Plus } from "lucide-react";
import { Paginacion, usePaginado } from "@/components/ui/Paginacion";
import { SearchInput } from "@/components/ui/SearchInput";
import { IconoContacto, type TipoContacto } from "./Buscador";
import { EmpresaFormPanel, NuevaPersonaPanel } from "./ContactoFormPanel";

export type FilaContacto = { id: string; nombre: string; detalle: string | null; activo: boolean };

const TEXTOS = {
  persona: {
    etiqueta: "personas",
    buscar: "Buscar persona…",
    nueva: "Nueva persona",
    vacio: 'Tu agenda: las personas que cargaste o te pasaron. Las que ves por una obra están en la obra. Creá una con "Nueva persona".',
  },
  empresa: {
    etiqueta: "empresas",
    buscar: "Buscar empresa…",
    nueva: "Nueva empresa",
    vacio: 'Las empresas de tu equipo. Creá una con "Nueva empresa".',
  },
};

export function ContactosView({ tipo, filas }: { tipo: TipoContacto; filas: FilaContacto[] }) {
  const [texto, setTexto] = useState("");
  const [creando, setCreando] = useState(false);
  const t = TEXTOS[tipo];

  const q = texto.trim().toLowerCase();
  const filtradas = filas.filter((f) => f.nombre.toLowerCase().includes(q));
  const { visibles, ...paginado } = usePaginado(filtradas);

  return (
    <div>
      <div className="mb-4 flex flex-wrap items-center gap-3">
        <SearchInput value={texto} onChange={setTexto} placeholder={t.buscar} />
        <button className="btn btn-primary" onClick={() => setCreando(true)}>
          <Plus size={16} />
          {t.nueva}
        </button>
      </div>

      <Paginacion {...paginado} etiqueta={t.etiqueta} />

      {filtradas.length === 0 ? (
        <div className="empty-state">
          <p className="t-h3">{filas.length === 0 ? `Sin ${t.etiqueta} todavía` : "Sin resultados"}</p>
          <p className="t-body-m mt-1">{filas.length === 0 ? t.vacio : "Probá con otro nombre."}</p>
        </div>
      ) : (
        <div className="flex flex-col rounded-lg border border-border bg-bg-surface">
          {visibles.map((f) => (
            <Link
              key={f.id}
              href={`/contactos/${tipo === "persona" ? "personas" : "empresas"}/${f.id}`}
              className="row flex items-center gap-3 border-b border-border last:border-b-0 hover:bg-bg-subtle"
            >
              <IconoContacto tipo={tipo} />
              <div className="min-w-0 flex-1">
                <p className="t-body-m truncate font-medium text-text-primary">{f.nombre}</p>
                {f.detalle && <p className="t-caption truncate">{f.detalle}</p>}
              </div>
              {!f.activo && <span className="badge badge-neutral">Desactivada</span>}
              <ChevronRight size={16} strokeWidth={1.75} className="shrink-0 text-text-tertiary" />
            </Link>
          ))}
        </div>
      )}

      {creando &&
        (tipo === "persona" ? (
          <NuevaPersonaPanel onClose={() => setCreando(false)} />
        ) : (
          <EmpresaFormPanel onClose={() => setCreando(false)} />
        ))}
    </div>
  );
}
