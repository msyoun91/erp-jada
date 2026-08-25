"use client";

import { useState } from "react";
import { Archive, Building2, Pencil } from "lucide-react";
import { toast } from "sonner";
import { ConfirmModal } from "@/components/ui/Modal";
import { OverflowMenu } from "@/components/ui/OverflowMenu";
import { Paginacion, usePaginado } from "@/components/ui/Paginacion";
import { SearchInput } from "@/components/ui/SearchInput";
import { desactivarEmpresa } from "../actions";
import type { Empresa } from "../types";
import { EmpresaFormPanel } from "./EmpresaFormPanel";
import { normalizar } from "./comercialLabels";

export function EmpresasView({
  empresas,
  puedeGestionar,
}: {
  empresas: Empresa[];
  puedeGestionar: boolean;
}) {
  const [texto, setTexto] = useState("");
  const [creando, setCreando] = useState(false);
  const [editando, setEditando] = useState<Empresa | null>(null);
  const [desactivando, setDesactivando] = useState<Empresa | null>(null);

  async function onDesactivar(empresa: Empresa) {
    const result = await desactivarEmpresa(empresa.id);
    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success("Empresa desactivada");
  }

  const q = normalizar(texto);
  const filtradas = empresas.filter(
    (e) =>
      normalizar(e.razon_social).includes(q) ||
      normalizar(e.nombre_comercial ?? "").includes(q) ||
      (e.cuit ?? "").includes(texto.replace(/\D/g, "")) ||
      normalizar(e.localidad ?? "").includes(q)
  );
  const { visibles, ...paginado } = usePaginado(filtradas);

  return (
    <div>
      <div className="mb-4 flex flex-wrap items-center gap-3">
        <SearchInput
          value={texto}
          onChange={setTexto}
          placeholder="Buscar por razón social, CUIT o localidad…"
        />
        {puedeGestionar && (
          <button className="btn btn-primary" onClick={() => setCreando(true)}>
            <Building2 size={16} />
            Nueva empresa
          </button>
        )}
      </div>

      <Paginacion {...paginado} etiqueta="empresas" />

      {filtradas.length === 0 ? (
        <div className="empty-state">
          <p className="t-h3">{texto ? "Sin resultados" : "Sin empresas todavía"}</p>
          <p className="t-body-m mt-1">
            {texto
              ? "Probá con otro término de búsqueda."
              : 'Cargá la primera con "Nueva empresa".'}
          </p>
        </div>
      ) : (
        <div className="flex flex-col rounded-lg border border-border bg-bg-surface">
          {visibles.map((empresa) => (
            <div
              key={empresa.id}
              className="flex items-center gap-2 border-b border-border p-[13px] px-5 last:border-b-0"
            >
              <div className="min-w-0 flex-1">
                <p className="t-body-m truncate font-medium text-text-primary">
                  {empresa.razon_social}
                </p>
                <p className="t-caption truncate">
                  {[
                    empresa.nombre_comercial,
                    empresa.cuit && `CUIT ${empresa.cuit}`,
                    empresa.localidad,
                    empresa.telefono,
                  ]
                    .filter(Boolean)
                    .join(" · ") || "Sin datos de contacto"}
                </p>
              </div>

              {puedeGestionar && (
                <OverflowMenu
                  items={[
                    {
                      label: "Modificar",
                      icon: <Pencil size={14} strokeWidth={1.75} />,
                      onClick: () => setEditando(empresa),
                    },
                    {
                      label: "Desactivar",
                      icon: <Archive size={14} strokeWidth={1.75} />,
                      onClick: () => setDesactivando(empresa),
                      destructive: true,
                    },
                  ]}
                />
              )}
            </div>
          ))}
        </div>
      )}

      {creando && <EmpresaFormPanel empresas={empresas} onClose={() => setCreando(false)} />}

      {editando && (
        <EmpresaFormPanel
          empresa={editando}
          empresas={empresas}
          onClose={() => setEditando(null)}
        />
      )}

      {desactivando && (
        <ConfirmModal
          title="Desactivar empresa"
          mensaje={`¿Desactivar ${desactivando.razon_social}? Si participa en alguna obra hay que sacarla de esa obra primero.`}
          onConfirm={() => onDesactivar(desactivando)}
          onClose={() => setDesactivando(null)}
        />
      )}
    </div>
  );
}
