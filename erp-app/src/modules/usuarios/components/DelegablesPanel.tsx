"use client";

import { useMemo, useState } from "react";
import { toast } from "sonner";
import { RightPanel } from "@/components/ui/RightPanel";
import { fijarDelegables } from "../actions";
import type { Submodulo } from "../types";
import { labelModulo } from "./PermisosPanel";

export function DelegablesPanel({
  submodulos,
  onClose,
}: {
  submodulos: Submodulo[];
  onClose: () => void;
}) {
  // Los de usuarios nunca se delegan (CHECK en la base): es lo que impide la
  // cadena de delegadores.
  const candidatos = submodulos.filter((s) => s.modulo !== "usuarios");
  const original = useMemo(
    () => new Set(submodulos.filter((s) => s.delegable).map((s) => s.id)),
    [submodulos],
  );
  const [marcados, setMarcados] = useState<Set<string>>(new Set(original));
  const [enviando, setEnviando] = useState(false);

  const quitados = [...original].filter((id) => !marcados.has(id)).length;
  const hayCambios =
    quitados > 0 || [...marcados].some((id) => !original.has(id));

  function toggle(id: string) {
    setMarcados((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }

  async function guardar() {
    setEnviando(true);
    const result = await fijarDelegables({ submodulo_ids: [...marcados] });
    setEnviando(false);

    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success("Permisos delegables actualizados");
    onClose();
  }

  const porModulo = Object.groupBy(candidatos, (s) => s.modulo);

  return (
    <RightPanel
      title="Permisos delegables"
      subtitle="Lo que un delegador puede repartir en su equipo"
      onClose={onClose}
      hayCambios={hayCambios}
      footer={
        <>
          <div className="flex-1 t-caption">
            {quitados > 0 &&
              `Desmarcar revoca lo que ya se delegó de ${quitados === 1 ? "ese permiso" : "esos permisos"}`}
          </div>
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
            disabled={enviando || !hayCambios}
          >
            {enviando ? "Guardando…" : "Guardar"}
          </button>
        </>
      }
    >
      <div className="flex min-h-0 flex-1 flex-col overflow-y-auto">
        {candidatos.length === 0 ? (
          <p className="t-body-m px-5 py-4">
            Todavía no hay permisos que se puedan delegar: los de Usuarios nunca se delegan.
          </p>
        ) : (
          <>
            <p className="t-caption px-5 pt-3">
              Un delegador solo reparte lo que está marcado acá y además tiene él.
            </p>
            {Object.entries(porModulo).map(([modulo, items]) => (
              <div key={modulo} className="border-b border-border py-2 last:border-b-0">
                <p className="t-body-m px-5 pb-1 pt-2 font-semibold text-text-primary">
                  {labelModulo(modulo)}
                </p>
                {items?.map((s) => (
                  <label
                    key={s.id}
                    className="flex cursor-pointer items-center gap-3 py-2.5 pl-8 pr-5 hover:bg-bg-subtle"
                  >
                    <input
                      type="checkbox"
                      checked={marcados.has(s.id)}
                      onChange={() => toggle(s.id)}
                      className="h-4 w-4 shrink-0 accent-brand-700"
                    />
                    <span className="truncate t-body-m text-text-primary">{s.nombre}</span>
                    <span className={`badge shrink-0 ${s.tipo === "vista" ? "badge-info" : "badge-neutral"}`}>
                      {s.tipo === "vista" ? "Vista" : "Función"}
                    </span>
                  </label>
                ))}
              </div>
            ))}
          </>
        )}
      </div>
    </RightPanel>
  );
}
