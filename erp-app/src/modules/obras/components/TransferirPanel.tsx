"use client";

import { useEffect, useState } from "react";
import { toast } from "sonner";
import { RightPanel } from "@/components/ui/RightPanel";
import { candidatosTransferencia, transferirObra } from "../actions";
import type { CandidatoTransferencia, EstadoTransferencia, Usuario } from "../types";
import { ChecklistTransferencia, estadosIniciales } from "./ChecklistTransferencia";

// Transferir cambia quién ve la obra, no solo una etiqueta: el responsable es
// el eje de la RLS. Y por cada contacto vinculado hay tres destinos posibles
// (sql/087), así que el panel pregunta uno por uno en vez de asumir.
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
  const [candidatos, setCandidatos] = useState<CandidatoTransferencia[]>([]);
  const [estados, setEstados] = useState<Map<string, EstadoTransferencia>>(new Map());

  useEffect(() => {
    candidatosTransferencia("obra", obraId).then((r) => {
      setCandidatos(r);
      setEstados(estadosIniciales(r));
    });
  }, [obraId]);

  async function transferir() {
    if (!destino) return setError("Elegí a quién transferirla");

    setError(undefined);
    setEnviando(true);
    const result = await transferirObra({
      obra_id: obraId,
      a_usuario_id: destino,
      migran: candidatos.filter((c) => estados.get(c.id) !== "queda").map((c) => c.id),
      sacar: candidatos.filter((c) => estados.get(c.id) === "saco").map((c) => c.id),
    });
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
      hayCambios={!!destino || [...estados.values()].some((e) => e !== "va")}
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
            aria-required
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

        {candidatos.length > 0 && (
          <div>
            <p className="t-label mb-1">Qué pasa con cada contacto de esta obra</p>
            <p className="t-caption mb-2">
              Elegí uno por uno. Lo que está en fichas de otros usuarios no se toca.
            </p>
            <ChecklistTransferencia
              candidatos={candidatos}
              estados={estados}
              onCambio={setEstados}
            />
          </div>
        )}

        <p className="t-caption">
          El responsable es quien ve la obra. Al transferirla dejás de verla, salvo que puedas
          transferir obras. Queda registrado quién la pasó y a quién.
        </p>
      </div>
    </RightPanel>
  );
}
