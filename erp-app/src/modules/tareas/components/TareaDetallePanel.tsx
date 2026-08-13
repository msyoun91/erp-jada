"use client";

import { useEffect, useState } from "react";
import { toast } from "sonner";
import { RightPanel } from "@/components/ui/RightPanel";
import { asociarTareaHilo, obtenerNotasTarea } from "../actions";
import type { TareaConRelaciones, TareaHilo, TareaNota } from "../types";
import { HiloBuscador } from "./HiloBuscador";
import { TareaNotasCard } from "./TareaNotasCard";

export function TareaDetallePanel({
  tarea,
  hilos,
  onClose,
}: {
  tarea: TareaConRelaciones;
  hilos: TareaHilo[];
  onClose: () => void;
}) {
  const [cargando, setCargando] = useState(true);
  const [notas, setNotas] = useState<TareaNota[]>([]);
  const [hiloId, setHiloId] = useState("");
  const [asociando, setAsociando] = useState(false);

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

  return (
    <RightPanel title={tarea.titulo} onClose={onClose}>
      <div className="min-h-0 flex-1 overflow-y-auto px-5 py-4">
        {cargando ? (
          <p className="t-caption">Cargando...</p>
        ) : (
          <>
            <TareaNotasCard tarea={tarea} notas={notas} onCambio={cargar} onEliminado={onClose} />

            {!tarea.hilo_id && (
              <div className="mt-4 border-t border-border pt-4">
                <label className="t-label mb-2 block">Asociar a un hilo</label>
                <HiloBuscador hilos={hilos} value={hiloId} onChange={setHiloId} />
                {hiloId && (
                  <button className="btn btn-primary btn-sm mt-2" onClick={onAsociar} disabled={asociando}>
                    {asociando ? "Asociando..." : "Asociar"}
                  </button>
                )}
              </div>
            )}
          </>
        )}
      </div>
    </RightPanel>
  );
}
