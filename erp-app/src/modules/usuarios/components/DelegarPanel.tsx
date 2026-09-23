"use client";

import { useMemo, useState } from "react";
import { toast } from "sonner";
import { AlertTriangle } from "lucide-react";
import { RightPanel } from "@/components/ui/RightPanel";
import { delegarSubmodulos } from "../actions";
import type { Miembro, Otorgamiento, Submodulo } from "../types";
import { labelModulo } from "./PermisosPanel";

// Espeja el techo de `sql/105` para no ofrecer lo que la base va a rechazar:
// el delegador ve lo delegable que él tiene, más todo lo que el miembro ya tiene.
// Lo que no otorgó él se muestra marcado y bloqueado.
export function DelegarPanel({
  miembro,
  yo,
  submodulos,
  permisos,
  puedeDelegar,
  onClose,
}: {
  miembro: Miembro;
  yo: string;
  submodulos: Submodulo[];
  permisos: Record<string, Otorgamiento[]>;
  puedeDelegar: boolean;
  onClose: () => void;
}) {
  const { original, ajenos, visibles } = useMemo(() => {
    const mios = new Set((permisos[yo] ?? []).map((p) => p.submodulo_id));
    const delMiembro = permisos[miembro.id] ?? [];
    const original = new Set(
      delMiembro.filter((p) => p.otorgada_por === yo).map((p) => p.submodulo_id),
    );
    const ajenos = new Set(
      delMiembro.filter((p) => p.otorgada_por !== yo).map((p) => p.submodulo_id),
    );
    const visibles = new Set(
      submodulos
        .filter((s) => (s.delegable && mios.has(s.id)) || original.has(s.id) || ajenos.has(s.id))
        .map((s) => s.id),
    );
    return { original, ajenos, visibles };
  }, [permisos, yo, miembro.id, submodulos]);

  const [seleccionados, setSeleccionados] = useState<Set<string>>(new Set(original));
  const [enviando, setEnviando] = useState(false);

  function toggle(id: string) {
    setSeleccionados((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }

  const marcado = (id: string) => ajenos.has(id) || seleccionados.has(id);

  // La vista puede venir de lo que dio el admin: se mira el resultado final.
  const huerfanas = submodulos.filter(
    (s) => s.tipo === "funcion" && s.vista_id && marcado(s.id) && !marcado(s.vista_id),
  ).length;

  let cambios = 0;
  for (const id of new Set([...original, ...seleccionados])) {
    if (original.has(id) !== seleccionados.has(id)) cambios++;
  }

  async function guardar() {
    setEnviando(true);
    const result = await delegarSubmodulos({
      usuario_id: miembro.id,
      submodulo_ids: [...seleccionados],
    });
    setEnviando(false);

    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success("Permisos actualizados");
    onClose();
  }

  const porModulo = Object.groupBy(
    submodulos.filter(
      (s) => visibles.has(s.id) || submodulos.some((f) => f.vista_id === s.id && visibles.has(f.id)),
    ),
    (s) => s.modulo,
  );

  function fila(s: Submodulo) {
    const bloqueado = ajenos.has(s.id) || !puedeDelegar;
    const esVista = s.tipo === "vista";
    const alcanzable = visibles.has(s.id);

    return (
      <label
        key={s.id}
        className={`flex items-center gap-3 py-2.5 pr-5 ${esVista ? "pl-5" : "pl-11"} ${
          bloqueado || !alcanzable ? "" : "cursor-pointer hover:bg-bg-subtle"
        }`}
      >
        <input
          type="checkbox"
          checked={marcado(s.id)}
          disabled={bloqueado || !alcanzable}
          onChange={() => toggle(s.id)}
          className="h-4 w-4 shrink-0 accent-brand-700"
        />
        <span className="truncate t-body-m text-text-primary">{s.nombre}</span>
        <span className={`badge shrink-0 ${esVista ? "badge-info" : "badge-neutral"}`}>
          {esVista ? "Vista" : "Función"}
        </span>
        {ajenos.has(s.id) && <span className="t-caption shrink-0">Asignado por el admin</span>}
        {!alcanzable && <span className="t-caption shrink-0">No la podés dar</span>}
        {!esVista && s.vista_id && marcado(s.id) && !marcado(s.vista_id) && (
          <AlertTriangle
            size={14}
            strokeWidth={1.75}
            className="shrink-0 text-warning-text"
            aria-label="Requiere que su vista esté autorizada"
          />
        )}
      </label>
    );
  }

  return (
    <RightPanel
      title="Permisos"
      subtitle={miembro.nombre}
      onClose={onClose}
      hayCambios={cambios > 0}
      footer={
        puedeDelegar ? (
          <>
            <div className="flex-1 t-caption">
              {huerfanas > 0
                ? `${huerfanas} función${huerfanas !== 1 ? "es" : ""} sin su vista`
                : cambios > 0 && `${cambios} cambio${cambios !== 1 ? "s" : ""} pendiente${cambios !== 1 ? "s" : ""}`}
            </div>
            <button type="button" className="btn btn-secondary btn-sm" onClick={onClose}>
              Cancelar
            </button>
            <button
              className="btn btn-primary btn-sm"
              onClick={guardar}
              disabled={enviando || cambios === 0 || huerfanas > 0}
            >
              {enviando ? "Guardando…" : "Guardar"}
            </button>
          </>
        ) : undefined
      }
    >
      {visibles.size === 0 ? (
        <div className="empty-state">
          <p className="t-h3">Nada para asignar</p>
          <p className="t-body-m mt-1">
            {miembro.nombre} no tiene permisos, y no tenés permisos delegables para darle. Los marca
            el administrador.
          </p>
        </div>
      ) : (
        <div className="flex-1 overflow-y-auto">
          {Object.entries(porModulo).map(([modulo, items]) => {
            if (!items) return null;
            const vistas = items.filter((s) => s.tipo === "vista").sort((a, b) => a.orden - b.orden);
            return (
              <div key={modulo} className="border-b border-border pb-1 last:border-b-0">
                <p className="px-5 pb-1 pt-3 t-body-m font-semibold text-text-primary">
                  {labelModulo(modulo)}
                </p>
                {vistas.map((vista) => (
                  <div key={vista.id}>
                    {fila(vista)}
                    {items
                      .filter((s) => s.tipo === "funcion" && s.vista_id === vista.id)
                      .map(fila)}
                  </div>
                ))}
              </div>
            );
          })}
        </div>
      )}
    </RightPanel>
  );
}
