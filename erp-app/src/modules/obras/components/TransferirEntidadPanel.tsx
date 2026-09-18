"use client";

import { useEffect, useState } from "react";
import { toast } from "sonner";
import { RightPanel } from "@/components/ui/RightPanel";
import { candidatosTransferencia, transferirEmpresa, transferirPersona } from "../actions";
import type { CandidatoTransferencia, EstadoTransferencia, Usuario } from "../types";
import {
  ChecklistTransferencia,
  estadosIniciales,
  tieneVinculosPropios,
} from "./ChecklistTransferencia";

// Transferir cambia el dueño (`creado_por`). La empresa pregunta por su gente;
// la persona no tiene nada colgando debajo, pero sí la misma elección sobre sí
// misma: si la saco, se desvincula de mis obras y mis empresas (sql/087).
export function TransferirEntidadPanel({
  tipo,
  id,
  nombre,
  duenioActual,
  usuarios,
  onClose,
}: {
  tipo: "persona" | "empresa";
  id: string;
  nombre: string;
  duenioActual: string | null;
  usuarios: Usuario[];
  onClose: () => void;
}) {
  const [destino, setDestino] = useState("");
  const [enviando, setEnviando] = useState(false);
  const [error, setError] = useState<string>();
  const [candidatos, setCandidatos] = useState<CandidatoTransferencia[]>([]);
  const [estados, setEstados] = useState<Map<string, EstadoTransferencia>>(new Map());

  useEffect(() => {
    candidatosTransferencia(tipo, id).then((r) => {
      setCandidatos(r);
      setEstados(estadosIniciales(r));
    });
  }, [tipo, id]);

  // La persona se transfiere a sí misma: su fila es la única del checklist y
  // decide si el saliente la sigue viendo o la suelta.
  const propia = candidatos.find((c) => c.id === id);
  const otros = candidatos.filter((c) => c.id !== id);

  async function transferir() {
    if (!destino) return setError("Elegí a quién transferirla");
    setError(undefined);
    setEnviando(true);
    const result =
      tipo === "persona"
        ? await transferirPersona({
            persona_id: id,
            a_usuario_id: destino,
            sacar: estados.get(id) === "saco",
          })
        : await transferirEmpresa({
            empresa_id: id,
            a_usuario_id: destino,
            migran: otros.filter((c) => estados.get(c.id) !== "queda").map((c) => c.id),
            sacar: otros.filter((c) => estados.get(c.id) === "saco").map((c) => c.id),
            sacar_empresa: estados.get(id) === "saco",
          });
    setEnviando(false);
    if (!result.success) return setError(result.error);
    toast.success(`${tipo === "persona" ? "Persona" : "Empresa"} transferida`);
    onClose();
  }

  return (
    <RightPanel
      title={`Transferir ${tipo}`}
      subtitle={nombre}
      onClose={onClose}
      hayCambios={!!destino || [...estados.values()].some((e) => e !== "va")}
      footer={
        <>
          <button type="button" className="btn btn-secondary btn-sm" onClick={onClose}>
            Cancelar
          </button>
          <button
            type="button"
            className="btn btn-primary btn-sm"
            onClick={transferir}
            disabled={enviando}
          >
            {enviando ? "Transfiriendo…" : "Transferir"}
          </button>
        </>
      }
    >
      <div className="flex flex-col gap-4 overflow-y-auto px-5 py-4">
        <p className="t-body-m">
          Dueño actual: <span className="font-semibold">{duenioActual ?? "—"}</span>
        </p>

        <div>
          <label className="t-label t-label-req mb-1 block">Nuevo dueño</label>
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

        {propia && tieneVinculosPropios(propia) && (
          <div>
            <p className="t-label mb-1">Qué pasa con tus vínculos</p>
            <ChecklistTransferencia
              candidatos={[propia]}
              estados={estados}
              onCambio={setEstados}
            />
          </div>
        )}

        {otros.length > 0 && (
          <div>
            <p className="t-label mb-1">Qué pasa con la gente de esta empresa</p>
            <p className="t-caption mb-2">
              Elegí una por una. Lo que está en fichas de otros usuarios no se toca.
            </p>
            <ChecklistTransferencia candidatos={otros} estados={estados} onCambio={setEstados} />
          </div>
        )}

        <p className="t-caption">
          El dueño ve la ficha y la edita. Los accesos que compartiste pasan al nuevo dueño, que es
          quien ahora puede revocarlos. Queda registrado.
        </p>
      </div>
    </RightPanel>
  );
}
