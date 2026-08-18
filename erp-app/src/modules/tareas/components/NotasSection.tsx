"use client";

import { useEffect, useState } from "react";
import { toast } from "sonner";
import { MessageSquarePlus } from "lucide-react";
import { agregarNotaHilo, agregarNotaTarea, listarNotasHilo, listarNotasTarea } from "../actions";
import type { HiloNota, TareaNota } from "../types";

// Reusado por TareaRow (notas de tarea) y HiloDetailPanel (notas de hilo) —
// mismo componente, cambia solo qué action llama. Fetch on-mount porque el
// componente solo se monta cuando el usuario abre la sección (no precarga
// notas de todo lo visible en la página).
export function NotasSection({
  tipo,
  id,
  puedeAgregar,
}: {
  tipo: "tarea" | "hilo";
  id: string;
  puedeAgregar: boolean;
}) {
  const [notas, setNotas] = useState<(TareaNota | HiloNota)[] | null>(null);
  const [nota, setNota] = useState("");
  const [enviando, setEnviando] = useState(false);

  useEffect(() => {
    let cancelado = false;
    async function cargar() {
      const result = tipo === "tarea" ? await listarNotasTarea(id) : await listarNotasHilo(id);
      if (!cancelado && result.success) setNotas(result.data);
    }
    cargar();
    return () => {
      cancelado = true;
    };
  }, [tipo, id]);

  async function agregar() {
    if (!nota.trim()) return;
    setEnviando(true);
    const result =
      tipo === "tarea"
        ? await agregarNotaTarea({ tarea_id: id, nota: nota.trim() })
        : await agregarNotaHilo({ hilo_id: id, nota: nota.trim() });
    setEnviando(false);

    if (!result.success) {
      toast.error(result.error);
      return;
    }
    setNota("");
    const refrescado = tipo === "tarea" ? await listarNotasTarea(id) : await listarNotasHilo(id);
    if (refrescado.success) setNotas(refrescado.data);
  }

  return (
    <div className="flex flex-col gap-2">
      {notas === null ? (
        <p className="t-caption">Cargando notas…</p>
      ) : notas.length === 0 ? (
        <p className="t-caption">Sin notas todavía.</p>
      ) : (
        <div className="flex flex-col gap-2">
          {notas.map((n) => (
            <div key={n.id} className="rounded-md bg-bg-subtle p-2">
              <p className="t-body-m whitespace-pre-wrap">{n.nota}</p>
              <p className="t-caption mt-1">
                {n.usuarios?.nombre ?? "—"} · {n.created_at.slice(0, 10)}
              </p>
            </div>
          ))}
        </div>
      )}

      {puedeAgregar && (
        <div className="flex items-end gap-2">
          <textarea
            rows={2}
            className="input flex-1"
            placeholder="Agregar nota…"
            value={nota}
            onChange={(e) => setNota(e.target.value)}
          />
          <button
            type="button"
            className="btn btn-secondary btn-sm shrink-0"
            onClick={agregar}
            disabled={enviando || !nota.trim()}
          >
            <MessageSquarePlus size={14} strokeWidth={1.75} />
            Agregar
          </button>
        </div>
      )}
    </div>
  );
}
