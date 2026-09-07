"use client";

import { useState } from "react";
import { toast } from "sonner";
import { RightPanel } from "@/components/ui/RightPanel";
import { vincularPersonaEmpresa } from "../actions";

// El cargo es de la relación persona↔empresa y no determina el rol en ninguna
// obra: son dos ejes distintos y no se infiere uno del otro.
export function VincularPersonaEmpresaPanel({
  personaId,
  empresas,
  onClose,
}: {
  personaId: string;
  empresas: { id: string; razon_social: string }[];
  onClose: () => void;
}) {
  const [empresaId, setEmpresaId] = useState("");
  const [cargo, setCargo] = useState("");
  const [esPrincipal, setEsPrincipal] = useState(false);
  const [enviando, setEnviando] = useState(false);
  const [error, setError] = useState<string>();

  async function guardar() {
    if (!empresaId) return setError("Elegí una empresa");

    setError(undefined);
    setEnviando(true);
    const result = await vincularPersonaEmpresa({
      persona_id: personaId,
      empresa_id: empresaId,
      cargo,
      es_principal: esPrincipal,
      observaciones: "",
    });
    setEnviando(false);

    if (!result.success) {
      setError(result.error);
      return;
    }
    toast.success("Empresa vinculada");
    onClose();
  }

  return (
    <RightPanel
      title="Vincular a una empresa"
      onClose={onClose}
      hayCambios={!!empresaId || !!cargo}
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
            className={`input ${error ? "input-error" : ""}`}
            value={empresaId}
            onChange={(e) => setEmpresaId(e.target.value)}
          >
            <option value="">Elegí una empresa…</option>
            {empresas.map((e) => (
              <option key={e.id} value={e.id}>
                {e.razon_social}
              </option>
            ))}
          </select>
          {error && <p className="input-error-text">{error}</p>}
        </div>

        <div>
          <label className="t-label mb-1 block">Cargo</label>
          <input
            className="input"
            placeholder="Compras, Socio, Director de obra…"
            value={cargo}
            onChange={(e) => setCargo(e.target.value)}
          />
        </div>

        <label className="flex min-h-[44px] items-center gap-2">
          <input
            type="checkbox"
            checked={esPrincipal}
            onChange={(e) => setEsPrincipal(e.target.checked)}
          />
          <span className="t-body-m">Es su empresa principal</span>
        </label>
        <p className="t-caption">Solo una empresa puede ser la principal de cada persona.</p>
      </div>
    </RightPanel>
  );
}
