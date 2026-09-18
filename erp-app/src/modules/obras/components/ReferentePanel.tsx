"use client";

import { useState } from "react";
import { toast } from "sonner";
import { RightPanel } from "@/components/ui/RightPanel";
import { guardarReferente } from "../actions";

// La comisión es de la relación obra↔referente: el mismo referente puede tener
// 3.50% acá y 2.00% en otra obra. Por eso el panel siempre nace desde una obra.
export function ReferentePanel({
  obraId,
  personas,
  referente,
  personaIdInicial,
  onClose,
}: {
  obraId: string;
  personas: { id: string; nombre: string }[];
  referente?: { persona_id: string; porcentaje_comision: number; observaciones: string | null };
  personaIdInicial?: string;
  onClose: () => void;
}) {
  const [personaId, setPersonaId] = useState(referente?.persona_id ?? personaIdInicial ?? "");
  const [comision, setComision] = useState(referente?.porcentaje_comision?.toString() ?? "");
  const [observaciones, setObservaciones] = useState(referente?.observaciones ?? "");
  const [enviando, setEnviando] = useState(false);
  // El campo viaja con el mensaje: un solo string se renderizaba en un lugar
  // fijo y "Elegí una persona" salía abajo de Comisión, pintándole el borde
  // rojo al input equivocado.
  const [error, setError] = useState<{ campo: "persona" | "comision"; mensaje: string }>();

  // Comparado contra lo que abrió el panel, no contra "hay algo puesto": al
  // modificar un referente los campos vienen llenos y cerrar sin tocar nada
  // preguntaba por cambios que no existen.
  const hayCambios =
    personaId !== (referente?.persona_id ?? personaIdInicial ?? "") ||
    comision !== (referente?.porcentaje_comision?.toString() ?? "") ||
    observaciones !== (referente?.observaciones ?? "");

  async function guardar() {
    if (!personaId) return setError({ campo: "persona", mensaje: "Elegí una persona" });
    // `z.coerce.number()` convierte "" en 0, así que sin este corte el panel
    // guardaba 0% en silencio con el campo marcado como obligatorio.
    if (!comision.trim()) {
      return setError({ campo: "comision", mensaje: "Poné el porcentaje — puede ser 0" });
    }

    setError(undefined);
    setEnviando(true);
    const result = await guardarReferente({
      obra_id: obraId,
      persona_id: personaId,
      porcentaje_comision: comision,
      observaciones,
    });
    setEnviando(false);

    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success("Referente guardado");
    onClose();
  }

  return (
    <RightPanel
      title={referente ? "Modificar referente" : "Marcar referente"}
      onClose={onClose}
      hayCambios={hayCambios}
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
          <label className="t-label t-label-req mb-1 block">Persona</label>
          <select
            aria-required
            className={`input ${error?.campo === "persona" ? "input-error" : ""}`}
            value={personaId}
            onChange={(e) => setPersonaId(e.target.value)}
            disabled={!!referente}
          >
            <option value="">Elegí una persona…</option>
            {personas.map((p) => (
              <option key={p.id} value={p.id}>
                {p.nombre}
              </option>
            ))}
          </select>
          {error?.campo === "persona" && <p className="input-error-text">{error.mensaje}</p>}
          <p className="t-caption mt-1">
            Solo personas ya vinculadas a esta obra. Vinculala primero si no aparece.
          </p>
        </div>

        <div>
          <label className="t-label t-label-req mb-1 block">Comisión (%)</label>
          <input
            type="number"
            step="0.01"
            min={0}
            max={100}
            aria-required
            className={`input ${error?.campo === "comision" ? "input-error" : ""}`}
            value={comision}
            onChange={(e) => setComision(e.target.value)}
          />
          {error?.campo === "comision" && <p className="input-error-text">{error.mensaje}</p>}
          <p className="t-caption mt-1">
            Esta fase solo registra la condición: no liquida ni calcula nada.
          </p>
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
  );
}
