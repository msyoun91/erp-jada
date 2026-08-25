"use client";

import { useState } from "react";
import { Archive, HardHat, Pencil } from "lucide-react";
import { toast } from "sonner";
import { ConfirmModal } from "@/components/ui/Modal";
import { OverflowMenu } from "@/components/ui/OverflowMenu";
import { Paginacion, usePaginado } from "@/components/ui/Paginacion";
import { SearchInput } from "@/components/ui/SearchInput";
import { desactivarObra } from "../actions";
import type { Empresa, ObraConRelaciones, PersonaConEmpresa } from "../types";
import {
  empresaPrincipal,
  ESTADO_OBRA_LABEL,
  nombreEmpresa,
  nombrePersona,
  normalizar,
  referente,
  TIPO_OBRA_LABEL,
} from "./comercialLabels";
import { ObraDetailPanel } from "./ObraDetailPanel";
import { ObraFormPanel } from "./ObraFormPanel";

export function ObrasView({
  obras,
  empresas,
  personas,
  puedeGestionar,
  verComision,
}: {
  obras: ObraConRelaciones[];
  empresas: Empresa[];
  personas: PersonaConEmpresa[];
  puedeGestionar: boolean;
  verComision: boolean;
}) {
  const [texto, setTexto] = useState("");
  const [creando, setCreando] = useState(false);
  const [editando, setEditando] = useState<ObraConRelaciones | null>(null);
  const [abierta, setAbierta] = useState<ObraConRelaciones | null>(null);
  const [desactivando, setDesactivando] = useState<ObraConRelaciones | null>(null);

  async function onDesactivar(obra: ObraConRelaciones) {
    const result = await desactivarObra(obra.id);
    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success("Obra desactivada");
  }

  const q = normalizar(texto);
  const filtradas = obras.filter(
    (o) =>
      normalizar(o.nombre).includes(q) ||
      normalizar(o.direccion ?? "").includes(q) ||
      normalizar(o.localidad ?? "").includes(q)
  );
  const { visibles, ...paginado } = usePaginado(filtradas);

  // El panel abierto se re-lee de `obras` en cada render: tras guardar una
  // relación el server component manda datos nuevos y el panel tiene que
  // mostrarlos, no la copia que se guardó al abrirlo.
  const obraAbierta = abierta ? (obras.find((o) => o.id === abierta.id) ?? null) : null;

  return (
    <div>
      <div className="mb-4 flex flex-wrap items-center gap-3">
        <SearchInput
          value={texto}
          onChange={setTexto}
          placeholder="Buscar por nombre, dirección o localidad…"
        />
        {puedeGestionar && (
          <button className="btn btn-primary" onClick={() => setCreando(true)}>
            <HardHat size={16} />
            Nueva obra
          </button>
        )}
      </div>

      <Paginacion {...paginado} etiqueta="obras" />

      {filtradas.length === 0 ? (
        <div className="empty-state">
          <p className="t-h3">{texto ? "Sin resultados" : "Sin obras todavía"}</p>
          <p className="t-body-m mt-1">
            {texto ? "Probá con otro término de búsqueda." : 'Cargá la primera con "Nueva obra".'}
          </p>
        </div>
      ) : (
        <div className="flex flex-col rounded-lg border border-border bg-bg-surface">
          {visibles.map((obra) => {
            const principal = empresaPrincipal(obra.obra_empresa);
            const quienRefirio = referente(obra.obra_persona);
            return (
              <div
                key={obra.id}
                className="flex items-center gap-2 border-b border-border p-[13px] px-5 last:border-b-0"
              >
                <button
                  className="min-w-0 flex-1 text-left"
                  onClick={() => setAbierta(obra)}
                  aria-label={`Ver ${obra.nombre}`}
                >
                  <p className="t-body-m truncate font-medium text-text-primary">{obra.nombre}</p>
                  <p className="t-caption truncate">
                    {[
                      obra.localidad,
                      TIPO_OBRA_LABEL[obra.tipo],
                      principal && nombreEmpresa(principal.empresas),
                      quienRefirio && `Ref. ${nombrePersona(quienRefirio.personas)}`,
                    ]
                      .filter(Boolean)
                      .join(" · ")}
                  </p>
                </button>

                <span className="badge badge-neutral shrink-0">
                  {ESTADO_OBRA_LABEL[obra.estado_obra]}
                </span>

                {puedeGestionar && (
                  <OverflowMenu
                    items={[
                      {
                        label: "Modificar",
                        icon: <Pencil size={14} strokeWidth={1.75} />,
                        onClick: () => setEditando(obra),
                      },
                      {
                        label: "Desactivar",
                        icon: <Archive size={14} strokeWidth={1.75} />,
                        onClick: () => setDesactivando(obra),
                        destructive: true,
                      },
                    ]}
                  />
                )}
              </div>
            );
          })}
        </div>
      )}

      {creando && <ObraFormPanel obras={obras} onClose={() => setCreando(false)} />}

      {editando && (
        <ObraFormPanel obra={editando} obras={obras} onClose={() => setEditando(null)} />
      )}

      {obraAbierta && (
        <ObraDetailPanel
          obra={obraAbierta}
          empresas={empresas}
          personas={personas}
          gestionar={puedeGestionar}
          verComision={verComision}
          onClose={() => setAbierta(null)}
        />
      )}

      {desactivando && (
        <ConfirmModal
          title="Desactivar obra"
          mensaje={`¿Desactivar ${desactivando.nombre}? Su prospecto y sus relaciones con empresas y personas se desactivan con ella.`}
          onConfirm={() => onDesactivar(desactivando)}
          onClose={() => setDesactivando(null)}
        />
      )}
    </div>
  );
}
