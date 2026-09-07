"use client";

import { useState } from "react";
import { toast } from "sonner";
import { RightPanel } from "@/components/ui/RightPanel";
import { editarVinculoEmpresa, vincularEmpresa } from "../actions";
import {
  LABEL_ROL_EMPRESA,
  ROLES_EMPRESA,
  type Empresa,
  type RolEmpresa,
} from "../types";
import { RolesPicker } from "./RolesPicker";
import { EmpresaFormPanel } from "./EmpresaFormPanel";

export type VinculoEmpresa = {
  id: string;
  empresa_id: string;
  roles: RolEmpresa[];
  observaciones: string | null;
};

export function VincularEmpresaPanel({
  obraId,
  empresas,
  vinculo,
  puedeCrearEmpresa,
  onClose,
}: {
  obraId: string;
  empresas: Empresa[];
  vinculo?: VinculoEmpresa;
  puedeCrearEmpresa: boolean;
  onClose: () => void;
}) {
  const [empresaId, setEmpresaId] = useState(vinculo?.empresa_id ?? "");
  const [roles, setRoles] = useState<RolEmpresa[]>(vinculo?.roles ?? []);
  const [observaciones, setObservaciones] = useState(vinculo?.observaciones ?? "");
  const [enviando, setEnviando] = useState(false);
  const [error, setError] = useState<string>();
  const [creandoEmpresa, setCreandoEmpresa] = useState(false);

  async function guardar() {
    if (!empresaId) return setError("Elegí una empresa");
    if (roles.length === 0) return setError("Elegí al menos un rol");

    setError(undefined);
    setEnviando(true);
    const datos = { obra_id: obraId, empresa_id: empresaId, roles, observaciones };
    const result = vinculo
      ? await editarVinculoEmpresa(vinculo.id, datos)
      : await vincularEmpresa(datos);
    setEnviando(false);

    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success(vinculo ? "Vínculo actualizado" : "Empresa vinculada");
    onClose();
  }

  return (
    <>
      <RightPanel
        title={vinculo ? "Modificar vínculo" : "Vincular empresa"}
        onClose={onClose}
        hayCambios={roles.length > 0 || !!empresaId}
        footer={
          <>
            <button type="button" className="btn btn-secondary btn-sm" onClick={onClose}>
              Cancelar
            </button>
            <button type="button" className="btn btn-primary btn-sm" onClick={guardar} disabled={enviando}>
              {enviando ? "Guardando…" : "Guardar"}
            </button>
          </>
        }
      >
        <div className="flex flex-col gap-4 overflow-y-auto px-5 py-4">
          <div>
            <label className="t-label t-label-req mb-1 block">Empresa</label>
            <select
              className="input"
              value={empresaId}
              onChange={(e) => setEmpresaId(e.target.value)}
              disabled={!!vinculo}
            >
              <option value="">Elegí una empresa…</option>
              {empresas.map((e) => (
                <option key={e.id} value={e.id}>
                  {e.razon_social}
                </option>
              ))}
            </select>
            {!vinculo && puedeCrearEmpresa && (
              <button
                type="button"
                className="btn btn-ghost btn-sm mt-1"
                onClick={() => setCreandoEmpresa(true)}
              >
                No está en la lista — crearla
              </button>
            )}
          </div>

          <div>
            <label className="t-label t-label-req mb-1 block">Roles en esta obra</label>
            {/* Una sola relación con varios roles: constructora y
                desarrolladora de la misma obra no son dos vínculos. */}
            <RolesPicker
              opciones={ROLES_EMPRESA}
              labels={LABEL_ROL_EMPRESA}
              seleccionados={roles}
              onChange={setRoles}
              error={error}
            />
          </div>

          <div>
            <label className="t-label mb-1 block">Observaciones</label>
            <textarea
              rows={3}
              className="input"
              value={observaciones}
              onChange={(e) => setObservaciones(e.target.value)}
            />
          </div>
        </div>
      </RightPanel>

      {creandoEmpresa && (
        <EmpresaFormPanel onClose={() => setCreandoEmpresa(false)} onCreada={setEmpresaId} />
      )}
    </>
  );
}
