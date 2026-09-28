"use client";

import { useState } from "react";
import Link from "next/link";
import { ChevronRight, MapPin, Plus, ShieldCheck, UserRound } from "lucide-react";
import { Paginacion, usePaginado } from "@/components/ui/Paginacion";
import { SearchInput } from "@/components/ui/SearchInput";
import type { ObraResumen } from "../queries";
import { ESTADOS_ABIERTOS, LABEL_ESTADO, type EstadoObra } from "../types";
import { AltaObraPanel, type QuienSlot } from "./ObraFormPanel";

const FILTROS = [
  { valor: "abiertas", label: "Abiertas" },
  { valor: "contratada", label: "Contratadas" },
  { valor: "perdida", label: "Perdidas" },
  { valor: "todas", label: "Todas" },
] as const;

type Filtro = (typeof FILTROS)[number]["valor"] | "huerfanas" | "persona";

// Todas: `todas` trae los que pueden recibir (activos con `obras_ver`, como
// `obras_avisar_huerfanas`) y `responsable` llega del aviso "obras huérfanas".
type Todas = { recibibles: string[]; responsable: string | null };

function pasa(filtro: Filtro, o: ObraResumen, todas?: Todas) {
  if (filtro === "todas") return true;
  if (filtro === "abiertas") return (ESTADOS_ABIERTOS as readonly EstadoObra[]).includes(o.estado);
  if (filtro === "huerfanas") return o.activo && !todas?.recibibles.includes(o.responsable_id);
  if (filtro === "persona") return o.activo && o.responsable_id === todas?.responsable;
  return filtro === o.estado;
}

// `Quien` llega solo si quien mira puede crear: el alta lo necesita y `app/`
// lo compone desde Contactos. `porAprobar`, solo con `obras_aprobar`.
export function ObrasView({
  obras,
  yo,
  nombres,
  Quien,
  todas,
  porAprobar,
}: {
  obras: ObraResumen[];
  yo: string;
  nombres: Record<string, string>;
  Quien?: QuienSlot;
  todas?: Todas;
  porAprobar?: number;
}) {
  const [texto, setTexto] = useState("");
  const [filtro, setFiltro] = useState<Filtro>(todas?.responsable ? "persona" : "abiertas");
  const [creando, setCreando] = useState(false);

  const q = texto.trim().toLowerCase();
  const filtradas = obras.filter(
    (o) =>
      pasa(filtro, o, todas) &&
      [o.nombre, o.direccion, o.localidad ?? ""].some((t) => t.toLowerCase().includes(q))
  );
  const { visibles, ...paginado } = usePaginado(filtradas);

  return (
    <div>
      <div className="mb-4 flex flex-wrap items-center gap-3">
        <SearchInput value={texto} onChange={setTexto} placeholder="Buscar por nombre o dirección…" />
        <select
          className="input w-auto"
          value={filtro}
          onChange={(e) => setFiltro(e.target.value as Filtro)}
          aria-label="Filtrar por estado"
        >
          {FILTROS.map((f) => (
            <option key={f.valor} value={f.valor}>
              {f.label}
            </option>
          ))}
          {todas && <option value="huerfanas">Huérfanas</option>}
          {todas?.responsable && <option value="persona">De {nombres[todas.responsable] ?? "—"}</option>}
        </select>
        {porAprobar !== undefined && (
          <Link href="/obras/por-aprobar" className="btn btn-secondary">
            <ShieldCheck size={16} />
            Por aprobar{porAprobar > 0 && <span className="badge badge-warning">{porAprobar}</span>}
          </Link>
        )}
        {Quien && (
          <button className="btn btn-primary" onClick={() => setCreando(true)}>
            <Plus size={16} />
            Nueva obra
          </button>
        )}
      </div>

      <Paginacion {...paginado} etiqueta="obras" />

      {filtradas.length === 0 ? (
        <div className="empty-state">
          <p className="t-h3">{obras.length === 0 ? "Sin obras todavía" : "Sin resultados"}</p>
          <p className="t-body-m mt-1">
            {obras.length === 0
              ? `Acá aparecen las obras que llevás y en las que participás.${Quien ? ' Cargá una con "Nueva obra".' : ""}`
              : filtro === "huerfanas"
                ? "Ninguna obra activa quedó sin quien la trabaje."
                : "Probá con otro término o cambiá el filtro de estado."}
          </p>
        </div>
      ) : (
        <div className="flex flex-col rounded-lg border border-border bg-bg-surface">
          {visibles.map((o) => (
            <Link
              key={o.id}
              href={`/obras/${o.id}`}
              className="row flex items-center gap-3 border-b border-border last:border-b-0 hover:bg-bg-subtle"
            >
              <div className="min-w-0 flex-1">
                <p className="t-body-m truncate font-medium text-text-primary">{o.nombre}</p>
                <p className="t-caption flex flex-wrap items-center gap-x-3 gap-y-1">
                  <span className="flex min-w-0 items-center gap-1">
                    <MapPin size={12} strokeWidth={1.75} />
                    <span className="truncate">{o.localidad ? `${o.direccion}, ${o.localidad}` : o.direccion}</span>
                  </span>
                  <span className="flex items-center gap-1">
                    <UserRound size={12} strokeWidth={1.75} />
                    {o.responsable_id === yo ? "Vos" : (nombres[o.responsable_id] ?? "—")}
                  </span>
                </p>
              </div>
              {!o.activo && <span className="badge badge-neutral">Desactivada</span>}
              {o.activo && o.congelada && <span className="badge badge-warning">Por aprobar</span>}
              <span className={`badge ${LABEL_ESTADO[o.estado].badge}`}>{LABEL_ESTADO[o.estado].label}</span>
              <ChevronRight size={16} strokeWidth={1.75} className="shrink-0 text-text-tertiary" />
            </Link>
          ))}
        </div>
      )}

      {creando && Quien && <AltaObraPanel Quien={Quien} onClose={() => setCreando(false)} />}
    </div>
  );
}
