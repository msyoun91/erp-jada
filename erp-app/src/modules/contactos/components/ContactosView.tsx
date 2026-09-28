"use client";

import { useState } from "react";
import Link from "next/link";
import { ChevronRight, Plus } from "lucide-react";
import { Paginacion, usePaginado } from "@/components/ui/Paginacion";
import { SearchInput } from "@/components/ui/SearchInput";
import { IconoContacto, type TipoContacto } from "./Buscador";
import { EmpresaFormPanel, NuevaPersonaPanel } from "./ContactoFormPanel";

export type FilaContacto = {
  id: string;
  nombre: string;
  detalle: string | null;
  activo: boolean;
  huerfana: boolean;
  responsable_id: string | null;
};

// Solo con `contactos_administrar`: el filtro "huérfanas" y, desde el aviso
// "personas huérfanas", las de quien se fue (`?responsable=`).
export type Administrar = { de: { id: string; nombre: string } | null };

type Filtro = "todas" | "huerfanas" | "de";

const TEXTOS = {
  persona: {
    etiqueta: "personas",
    buscar: "Buscar persona…",
    nueva: "Nueva persona",
    vacio: 'Tu agenda: las personas que cargaste o te pasaron. Las que ves por una obra están en la obra. Creá una con "Nueva persona".',
    sinHuerfanas: "Ninguna persona activa quedó sin dueño que la vea.",
  },
  empresa: {
    etiqueta: "empresas",
    buscar: "Buscar empresa…",
    nueva: "Nueva empresa",
    vacio: 'Las empresas de tu equipo. Creá una con "Nueva empresa".',
    sinHuerfanas: "Ninguna empresa activa quedó sin equipo ni quien la vea.",
  },
};

function pasa(filtro: Filtro, f: FilaContacto, de: string | undefined) {
  if (filtro === "huerfanas") return f.huerfana;
  if (filtro === "de") return f.activo && f.responsable_id === de;
  return true;
}

export function ContactosView({
  tipo,
  filas,
  administrar,
}: {
  tipo: TipoContacto;
  filas: FilaContacto[];
  administrar?: Administrar;
}) {
  const [texto, setTexto] = useState("");
  const [filtro, setFiltro] = useState<Filtro>(administrar?.de ? "de" : "todas");
  const [creando, setCreando] = useState(false);
  const t = TEXTOS[tipo];

  const q = texto.trim().toLowerCase();
  const filtradas = filas.filter((f) => pasa(filtro, f, administrar?.de?.id) && f.nombre.toLowerCase().includes(q));
  const { visibles, ...paginado } = usePaginado(filtradas);

  return (
    <div>
      <div className="mb-4 flex flex-wrap items-center gap-3">
        <SearchInput value={texto} onChange={setTexto} placeholder={t.buscar} />
        {administrar && (
          <select
            className="input w-auto"
            value={filtro}
            onChange={(e) => setFiltro(e.target.value as Filtro)}
            aria-label="Filtrar"
          >
            <option value="todas">Todas</option>
            <option value="huerfanas">Huérfanas</option>
            {administrar.de && <option value="de">De {administrar.de.nombre}</option>}
          </select>
        )}
        <button className="btn btn-primary" onClick={() => setCreando(true)}>
          <Plus size={16} />
          {t.nueva}
        </button>
      </div>

      <Paginacion {...paginado} etiqueta={t.etiqueta} />

      {filtradas.length === 0 ? (
        <div className="empty-state">
          <p className="t-h3">{filas.length === 0 ? `Sin ${t.etiqueta} todavía` : "Sin resultados"}</p>
          <p className="t-body-m mt-1">
            {filas.length === 0 ? t.vacio : filtro === "huerfanas" && !q ? t.sinHuerfanas : "Probá con otro nombre."}
          </p>
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
