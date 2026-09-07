"use client";

import { useState } from "react";
import { toast } from "sonner";
import { RightPanel } from "@/components/ui/RightPanel";
import { transferirObra } from "../actions";
import type { Usuario } from "../types";

// Transferir cambia quién ve la obra, no solo una etiqueta: el responsable es
// el eje de la RLS. Por eso el panel lo dice antes de confirmar.
export function TransferirPanel({
  obraId,
  obraNombre,
  responsableActual,
  usuarios,
  onClose,
}: {
  obraId: string;
  obraNombre: string;
  responsableActual: string | null;
  usuarios: Usuario[];
  onClose: () => void;
}) {
  const [destino, setDestino] = useState("");
  const [enviando, setEnviando] = useState(false);
  const [error, setError] = useState<string>();

  async function transferir() {
    if (!destino) return setError("Elegí a quién transferirla");

    setError(undefined);
    setEnviando(true);
    const result = await transferirObra({ obra_id: obraId, a_usuario_id: destino });
    setEnviando(false);

    if (!result.success) {
      setError(result.error);
      return;
    }
    toast.success("Obra transferida");
    onClose();
  }

  return (
    <RightPanel
      title="Transferir obra"
      subtitle={obraNombre}
      onClose={onClose}
      hayCambios={!!destino}
      footer={
        <>
          <button type="button" className="btn btn-secondary btn-sm" onClick={onClose}>
            Cancelar
          </button>
          <button type="button" className="btn btn-primary btn-sm" onClick={transferir} disabled={enviando}>
            {enviando ? "Transfiriendo…" : "Transferir"}
          </button>
        </>
      }
    >
      <div className="flex flex-col gap-4 overflow-y-auto px-5 py-4">
        <p className="t-body-m">
          Responsable actual: <span className="font-semibold">{responsableActual ?? "—"}</span>
        </p>

        <div>
          <label className="t-label t-label-req mb-1 block">Nuevo responsable</label>
          <select
            className={`input ${error ? "input-error" : ""}`}
            value={destino}
            onChange={(e) => setDestino(e.target.value)}
          >
            <option value="">Elegí un usuario…</option>
            {usuarios.map((u) => (
              <option key={u.id} value={u.id}>
                {u.nombre}
              </option>
            ))}
          </select>
          {error && <p className="input-error-text">{error}</p>}
        </div>

        <p className="t-caption">
          El responsable es quien ve la obra. Al transferirla dejás de verla, salvo que puedas
          transferir obras. Queda registrado quién la pasó y a quién.
        </p>
      </div>
    </RightPanel>
  );
}
