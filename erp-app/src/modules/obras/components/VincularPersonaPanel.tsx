"use client";

import { useState } from "react";
import { toast } from "sonner";
import { RightPanel } from "@/components/ui/RightPanel";
import { buscarDuplicadosPersona, editarVinculoPersona, vincularPersona } from "../actions";
import {
  LABEL_ROL_PERSONA,
  ROLES_PERSONA,
  type DuplicadoPersona,
  type RolPersona,
} from "../types";
import { RolesPicker } from "./RolesPicker";
import { PersonaFormPanel } from "./PersonaFormPanel";

export type VinculoPersona = {
  id: string;
  persona_id: string;
  empresa_id: string | null;
  roles: RolPersona[];
  observaciones: string | null;
  nombre: string;
};

// La persona se elige por búsqueda, no por lista desplegable: la agenda no es
// global. La búsqueda devuelve identidad mínima — nombre y empresa, nunca
// contacto — y vincularla a esta obra es lo que después da acceso a la ficha.
export function VincularPersonaPanel({
  obraId,
  empresas,
  vinculo,
  puedeCrearPersona,
  onClose,
}: {
  obraId: string;
  empresas: { id: string; razon_social: string }[];
  vinculo?: VinculoPersona;
  puedeCrearPersona: boolean;
  onClose: () => void;
}) {
  const [busqueda, setBusqueda] = useState("");
  const [resultados, setResultados] = useState<DuplicadoPersona[]>([]);
  const [buscando, setBuscando] = useState(false);
  const [personaId, setPersonaId] = useState(vinculo?.persona_id ?? "");
  const [personaNombre, setPersonaNombre] = useState(vinculo?.nombre ?? "");
  const [empresaId, setEmpresaId] = useState(vinculo?.empresa_id ?? "");
  const [roles, setRoles] = useState<RolPersona[]>(vinculo?.roles ?? []);
  const [observaciones, setObservaciones] = useState(vinculo?.observaciones ?? "");
  const [enviando, setEnviando] = useState(false);
  const [error, setError] = useState<string>();
  const [creandoPersona, setCreandoPersona] = useState(false);

  async function buscar() {
    if (!busqueda.trim()) return;
    setBuscando(true);
    setResultados(await buscarDuplicadosPersona(busqueda));
    setBuscando(false);
  }

  function elegir(d: DuplicadoPersona) {
    setPersonaId(d.persona_id);
    setPersonaNombre(`${d.nombre} ${d.apellido ?? ""}`.trim());
    setResultados([]);
  }

  async function guardar() {
    if (!personaId) return setError("Elegí una persona");
    if (roles.length === 0) return setError("Elegí al menos un rol");

    setError(undefined);
    setEnviando(true);
    const datos = {
      obra_id: obraId,
      persona_id: personaId,
      empresa_id: empresaId,
      roles,
      observaciones,
    };
    const result = vinculo
      ? await editarVinculoPersona(vinculo.id, datos)
      : await vincularPersona(datos);
    setEnviando(false);

    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success(vinculo ? "Vínculo actualizado" : "Persona vinculada");
    onClose();
  }

  return (
    <>
      <RightPanel
        title={vinculo ? "Modificar vínculo" : "Vincular persona"}
        subtitle={personaNombre || undefined}
        onClose={onClose}
        hayCambios={!!personaId || roles.length > 0}
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
          {!vinculo && (
            <div>
              <label className="t-label t-label-req mb-1 block">Persona</label>
              {personaId ? (
                <div className="flex items-center gap-2">
                  <span className="t-body-m flex-1 font-semibold">{personaNombre}</span>
                  <button
                    type="button"
                    className="btn btn-ghost btn-sm"
                    onClick={() => {
                      setPersonaId("");
                      setPersonaNombre("");
                    }}
                  >
                    Cambiar
                  </button>
                </div>
              ) : (
                <>
                  <div className="flex gap-2">
                    <input
                      className="input"
                      placeholder="Nombre o apellido…"
                      value={busqueda}
                      onChange={(e) => setBusqueda(e.target.value)}
                      onKeyDown={(e) => e.key === "Enter" && (e.preventDefault(), buscar())}
                    />
                    <button type="button" className="btn btn-secondary btn-sm" onClick={buscar}>
                      {buscando ? "…" : "Buscar"}
                    </button>
                  </div>

                  {resultados.length > 0 && (
                    <ul className="mt-2 flex flex-col gap-1">
                      {resultados.map((d) => (
                        <li key={d.persona_id}>
                          <button
                            type="button"
                            className="card flex w-full min-h-[44px] items-center gap-2 p-2 text-left hover:bg-bg-subtle"
                            onClick={() => elegir(d)}
                          >
                            <span className="t-body-m flex-1 font-semibold">
                              {d.nombre} {d.apellido ?? ""}
                            </span>
                            {d.empresa && <span className="t-caption">{d.empresa}</span>}
                          </button>
                        </li>
                      ))}
                    </ul>
                  )}

                  {puedeCrearPersona && (
                    <button
                      type="button"
                      className="btn btn-ghost btn-sm mt-1"
                      onClick={() => setCreandoPersona(true)}
                    >
                      No aparece — crearla
                    </button>
                  )}
                </>
              )}
            </div>
          )}

          <div>
            <label className="t-label mb-1 block">A qué empresa representa acá</label>
            <select className="input" value={empresaId} onChange={(e) => setEmpresaId(e.target.value)}>
              <option value="">Sin especificar</option>
              {empresas.map((e) => (
                <option key={e.id} value={e.id}>
                  {e.razon_social}
                </option>
              ))}
            </select>
            <p className="t-caption mt-1">Es contexto de esta obra, no su empleador.</p>
          </div>

          <div>
            <label className="t-label t-label-req mb-1 block">Roles en esta obra</label>
            <RolesPicker
              opciones={ROLES_PERSONA}
              labels={LABEL_ROL_PERSONA}
              seleccionados={roles}
              onChange={setRoles}
              error={error}
            />
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

      {creandoPersona && (
        <PersonaFormPanel
          onClose={() => setCreandoPersona(false)}
          onCreada={(id) => {
            setPersonaId(id);
            setPersonaNombre(busqueda);
          }}
        />
      )}
    </>
  );
}
