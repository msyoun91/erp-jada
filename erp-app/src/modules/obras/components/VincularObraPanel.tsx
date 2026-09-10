"use client";

import { useState } from "react";
import { toast } from "sonner";
import { RightPanel } from "@/components/ui/RightPanel";
import { buscarObrasParaVincular, vincularEmpresa, vincularPersona } from "../actions";
import {
  LABEL_ROL_EMPRESA,
  LABEL_ROL_PERSONA,
  ROLES_EMPRESA,
  ROLES_PERSONA,
  type RolEmpresa,
  type RolPersona,
} from "../types";
import { Buscador } from "./Buscador";
import { RolesPicker } from "./RolesPicker";

// El otro sentido del vínculo obra↔entidad: hasta ahora solo se podía armar
// parado en la obra. Desde la ficha de la empresa o de la persona se elige la
// obra, que es como se piensa cuando uno viene de la agenda y no del listado.
//
// Solo aparecen las obras propias y no congeladas: son las únicas a las que la
// RLS deja colgarle un vínculo.
const buscarObras = (texto: string) => buscarObrasParaVincular(texto);

export function VincularObraPanel({
  empresa,
  persona,
  onClose,
}: {
  empresa?: { id: string; razon_social: string };
  persona?: { id: string; nombre: string };
  onClose: () => void;
}) {
  const [obraId, setObraId] = useState("");
  const [obraNombre, setObraNombre] = useState("");
  const [rolesEmpresa, setRolesEmpresa] = useState<RolEmpresa[]>([]);
  const [rolesPersona, setRolesPersona] = useState<RolPersona[]>([]);
  const [observaciones, setObservaciones] = useState("");
  const [enviando, setEnviando] = useState(false);
  const [error, setError] = useState<string>();

  const roles: string[] = empresa ? rolesEmpresa : rolesPersona;

  async function guardar() {
    if (!obraId) return setError("Elegí una obra");
    if (roles.length === 0) return setError("Elegí al menos un rol");

    setError(undefined);
    setEnviando(true);

    const result = empresa
      ? await vincularEmpresa({
          obra_id: obraId,
          empresa_id: empresa.id,
          roles: rolesEmpresa,
          observaciones,
          personas: [],
        })
      : await vincularPersona({
          obra_id: obraId,
          persona_id: persona!.id,
          empresa_id: "",
          roles: rolesPersona,
          observaciones,
        });

    setEnviando(false);

    if (!result.success) {
      toast.error(result.error);
      return;
    }

    toast.success("Vínculo creado");
    onClose();
  }

  return (
    <RightPanel
      title="Vincular a una obra"
      subtitle={empresa?.razon_social ?? persona?.nombre}
      onClose={onClose}
      hayCambios={!!obraId || roles.length > 0}
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
          <label className="t-label t-label-req mb-1 block">Obra</label>
          {obraId ? (
            <div className="flex items-center gap-2">
              <span className="t-body-m min-w-0 flex-1 truncate font-semibold">{obraNombre}</span>
              <button
                type="button"
                className="btn btn-ghost btn-sm"
                onClick={() => {
                  setObraId("");
                  setObraNombre("");
                }}
              >
                Cambiar
              </button>
            </div>
          ) : (
            <Buscador
              placeholder="Buscar entre tus obras…"
              buscar={buscarObras}
              error={error}
              onElegir={(o) => {
                setObraId(o.id);
                setObraNombre(o.etiqueta);
              }}
            />
          )}
        </div>

        <div>
          <label className="t-label t-label-req mb-1 block">
            {empresa ? "Roles de la empresa en esa obra" : "Roles de la persona en esa obra"}
          </label>
          {empresa ? (
            <RolesPicker
              opciones={ROLES_EMPRESA}
              labels={LABEL_ROL_EMPRESA}
              seleccionados={rolesEmpresa}
              onChange={setRolesEmpresa}
              error={error}
            />
          ) : (
            <RolesPicker
              opciones={ROLES_PERSONA}
              labels={LABEL_ROL_PERSONA}
              seleccionados={rolesPersona}
              onChange={setRolesPersona}
              error={error}
            />
          )}
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
