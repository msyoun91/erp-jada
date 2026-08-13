"use client";

import { useEffect, useState } from "react";
import { toast } from "sonner";
import { RightPanel } from "@/components/ui/RightPanel";
import { actualizarRecurrenciaTarea, asociarTareaHilo, obtenerNotasTarea } from "../actions";
import type { TareaConRelaciones, TareaHilo, TareaNota } from "../types";
import { HiloBuscador } from "./HiloBuscador";
import { RecurrenciaFields, type RecurrenciaValue } from "./RecurrenciaFields";
import { TareaNotasCard } from "./TareaNotasCard";

export function TareaDetallePanel({
  tarea,
  hilos,
  usuarios,
  puedeAsignar,
  onClose,
}: {
  tarea: TareaConRelaciones;
  hilos: TareaHilo[];
  usuarios: { id: string; nombre: string }[];
  puedeAsignar: boolean;
  onClose: () => void;
}) {
  const [cargando, setCargando] = useState(true);
  const [notas, setNotas] = useState<TareaNota[]>([]);
  const [hiloId, setHiloId] = useState("");
  const [asociando, setAsociando] = useState(false);
  const [recurrencia, setRecurrencia] = useState<RecurrenciaValue>({
    recurrencia_activa: tarea.recurrencia_activa,
    recurrencia_una_vez: tarea.recurrencia_una_vez,
    recurrencia_intervalo: tarea.recurrencia_intervalo ?? "mes",
    recurrencia_cada: tarea.recurrencia_cada,
    recurrencia_proxima: tarea.recurrencia_proxima ?? "",
  });
  const [guardandoRecurrencia, setGuardandoRecurrencia] = useState(false);

  async function cargar() {
    setNotas(await obtenerNotasTarea(tarea.id));
    setCargando(false);
  }

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect -- fetch on demand al abrir el panel, no dato inicial de página
    cargar();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tarea.id]);

  async function onAsociar() {
    if (!hiloId) return;
    setAsociando(true);
    const result = await asociarTareaHilo({ tarea_id: tarea.id, hilo_id: hiloId });
    setAsociando(false);

    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success("Tarea asociada al hilo");
    onClose();
  }

  async function onGuardarRecurrencia() {
    if (recurrencia.recurrencia_activa && !recurrencia.recurrencia_proxima) {
      toast.error("Elegí la próxima fecha de repetición");
      return;
    }

    setGuardandoRecurrencia(true);
    const result = await actualizarRecurrenciaTarea({ tarea_id: tarea.id, ...recurrencia });
    setGuardandoRecurrencia(false);

    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success("Recurrencia actualizada");
    onClose();
  }

  return (
    <RightPanel title={tarea.titulo} onClose={onClose}>
      <div className="min-h-0 flex-1 overflow-y-auto px-5 py-4">
        {cargando ? (
          <p className="t-caption py-6 text-center">Cargando...</p>
        ) : (
          <>
            <TareaNotasCard
              tarea={tarea}
              notas={notas}
              usuarios={usuarios}
              puedeAsignar={puedeAsignar}
              onCambio={cargar}
              onEliminado={onClose}
              ocultarTitulo
            />

            {!tarea.hilo_id && (
              <>
                <div className="mt-4 border-t border-border pt-4">
                  <p className="t-label mb-2">Recurrencia</p>
                  <RecurrenciaFields value={recurrencia} onChange={setRecurrencia} />
                  <button
                    className="btn btn-primary btn-sm mt-3"
                    onClick={onGuardarRecurrencia}
                    disabled={guardandoRecurrencia}
                  >
                    {guardandoRecurrencia ? "Guardando..." : "Guardar recurrencia"}
                  </button>
                </div>

                <div className="mt-4 border-t border-border pt-4">
                  <label className="t-label mb-2 block">Asociar a un hilo</label>
                  <HiloBuscador hilos={hilos} value={hiloId} onChange={setHiloId} />
                  {hiloId && (
                    <button className="btn btn-primary btn-sm mt-2" onClick={onAsociar} disabled={asociando}>
                      {asociando ? "Asociando..." : "Asociar"}
                    </button>
                  )}
                </div>
              </>
            )}
          </>
        )}
      </div>
    </RightPanel>
  );
}
