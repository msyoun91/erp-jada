"use client";

import { useState } from "react";
import { Plus } from "lucide-react";
import { toast } from "sonner";
import { RightPanel } from "@/components/ui/RightPanel";
import { buscarDuplicadosPersona, editarVinculoPersona, vincularPersona } from "../actions";
import { LABEL_ROL_PERSONA, ROLES_PERSONA, type RolPersona } from "../types";
import { Buscador } from "./Buscador";
import { RolesPicker } from "./RolesPicker";
import { PersonaFormPanel } from "./PersonaFormPanel";

// Identidad mínima: nombre, apellido y empresa principal. Estable entre
// renders porque el <Buscador /> la toma como dependencia.
const buscarPersonas = async (texto: string) => {
  const encontradas = await buscarDuplicadosPersona(texto);
  return encontradas.map((d) => ({
    id: d.persona_id,
    etiqueta: `${d.nombre} ${d.apellido ?? ""}`.trim(),
    detalle: d.empresa,
  }));
};

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
  const [personaId, setPersonaId] = useState(vinculo?.persona_id ?? "");
  const [personaNombre, setPersonaNombre] = useState(vinculo?.nombre ?? "");
  const [empresaId, setEmpresaId] = useState(vinculo?.empresa_id ?? "");
  const [roles, setRoles] = useState<RolPersona[]>(vinculo?.roles ?? []);
  const [observaciones, setObservaciones] = useState(vinculo?.observaciones ?? "");
  const [enviando, setEnviando] = useState(false);
  const [error, setError] = useState<string>();
  const [creandoPersona, setCreandoPersona] = useState(false);

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

    // Vincular una persona que cargó otro queda esperando autorización, y
    // hasta entonces el vínculo no abre su ficha de contacto.
    if (!vinculo && "pendiente" in result && result.pendiente) {
      toast.warning("Persona vinculada, pendiente de autorización: la cargó otro usuario");
    } else {
      toast.success(vinculo ? "Vínculo actualizado" : "Persona vinculada");
    }
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
                  {/* Sin carga inicial: la agenda no se lista sola, se busca.
                      Es lo que evita que vincular sea una puerta al padrón. */}
                  <Buscador
                    placeholder="Nombre o apellido…"
                    buscar={buscarPersonas}
                    cargarAlAbrir={false}
                    onElegir={(o) => {
                      setPersonaId(o.id);
                      setPersonaNombre(o.etiqueta);
                    }}
                  />

                  {puedeCrearPersona && (
                    <button
                      type="button"
                      className="btn btn-secondary btn-sm mt-2"
                      onClick={() => setCreandoPersona(true)}
                    >
                      <Plus size={14} />
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
          onCreada={(id, pendiente, nombre) => {
            // Congelada no se puede vincular: el trigger corta con OB012.
            if (pendiente) return;
            setPersonaId(id);
            setPersonaNombre(nombre);
          }}
        />
      )}
    </>
  );
}
