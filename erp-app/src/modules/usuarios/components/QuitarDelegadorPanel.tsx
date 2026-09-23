"use client";

import { useState } from "react";
import { toast } from "sonner";
import { RightPanel } from "@/components/ui/RightPanel";
import { quitarDelegador } from "../actions";
import type { Submodulo, Usuario } from "../types";
import { labelModulo } from "./PermisosPanel";

// La delegación y su vista van siempre al heredero (US013): se muestran
// marcadas y bloqueadas para que la lista diga todo lo que recibe.
const SIEMPRE = ["usuarios_delegar", "usuarios_equipo"];

export function QuitarDelegadorPanel({
  saliente,
  companeros,
  submodulos,
  asignaciones,
  onClose,
}: {
  saliente: Usuario;
  companeros: Usuario[];
  submodulos: Submodulo[];
  asignaciones: Record<string, string[]>;
  onClose: () => void;
}) {
  const [herederoId, setHerederoId] = useState("");
  const [noCopiar, setNoCopiar] = useState<Set<string>>(new Set());
  const [enviando, setEnviando] = useState(false);

  const suyos = new Set(asignaciones[saliente.id] ?? []);
  const permisos = submodulos.filter((s) => suyos.has(s.id));
  const sinHeredero = companeros.length === 0;

  function toggle(id: string) {
    setNoCopiar((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }

  async function guardar() {
    setEnviando(true);
    const result = await quitarDelegador({
      saliente_id: saliente.id,
      heredero_id: herederoId || null,
      no_copiar: herederoId ? [...noCopiar] : [],
    });
    setEnviando(false);

    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success(`${saliente.nombre} ya no es el delegador`);
    onClose();
  }

  return (
    <RightPanel
      title="Quitar delegador"
      subtitle={saliente.nombre}
      onClose={onClose}
      hayCambios={herederoId !== "" || noCopiar.size > 0}
      footer={
        <>
          <div className="flex-1" />
          <button
            type="button"
            className="btn btn-secondary btn-sm"
            onClick={onClose}
            disabled={enviando}
          >
            Cancelar
          </button>
          <button
            className="btn btn-primary btn-sm"
            onClick={guardar}
            disabled={enviando || (!sinHeredero && !herederoId)}
          >
            {enviando ? "Guardando…" : "Quitar delegador"}
          </button>
        </>
      }
    >
      <div className="flex min-h-0 flex-1 flex-col overflow-y-auto">
        <div className="border-b border-border px-5 py-4">
          {sinHeredero ? (
            <p className="t-body-m">
              No queda otro miembro activo en el equipo: sale sin heredero y se revoca todo lo que
              delegó.
            </p>
          ) : (
            <>
              <label htmlFor="heredero" className="t-label t-label-req mb-1 block">
                Heredero
              </label>
              <select
                id="heredero"
                className="input"
                value={herederoId}
                onChange={(e) => setHerederoId(e.target.value)}
              >
                <option value="">— seleccionar —</option>
                {companeros.map((u) => (
                  <option key={u.id} value={u.id}>
                    {u.nombre}
                  </option>
                ))}
              </select>
              <p className="t-caption mt-1">
                Pasa a ser el delegador y se queda con lo que {saliente.nombre} repartió.{" "}
                {saliente.nombre} conserva el resto de sus permisos.
              </p>
            </>
          )}
        </div>

        {herederoId && (
          <div className="py-2">
            <p className="t-caption px-5 pb-1 pt-2">
              El heredero recibe una copia de estos permisos. Lo que desmarques se le revoca también
              a quien lo haya recibido por delegación.
            </p>
            {permisos.map((s) => {
              const fijo = SIEMPRE.includes(s.codigo);
              return (
                <label
                  key={s.id}
                  className={`flex items-center gap-3 px-5 py-2.5 ${fijo ? "" : "cursor-pointer hover:bg-bg-subtle"}`}
                >
                  <input
                    type="checkbox"
                    checked={fijo || !noCopiar.has(s.id)}
                    disabled={fijo}
                    onChange={() => toggle(s.id)}
                    className="h-4 w-4 shrink-0 accent-brand-700"
                  />
                  <span className="truncate t-body-m text-text-primary">
                    {labelModulo(s.modulo)} · {s.nombre}
                  </span>
                </label>
              );
            })}
          </div>
        )}
      </div>
    </RightPanel>
  );
}
