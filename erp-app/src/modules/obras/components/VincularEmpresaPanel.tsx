"use client";

import { useState } from "react";
import { Plus } from "lucide-react";
import { toast } from "sonner";
import { RightPanel } from "@/components/ui/RightPanel";
import {
  buscarEmpresasParaVincular,
  editarVinculoEmpresa,
  personasDeEmpresa,
  vincularEmpresa,
} from "../actions";
import {
  LABEL_ROL_EMPRESA,
  LABEL_ROL_PERSONA,
  ROLES_EMPRESA,
  ROLES_PERSONA,
  type PersonaDeEmpresa,
  type RolEmpresa,
  type RolPersona,
} from "../types";
import { Buscador } from "./Buscador";
import { RolesPicker } from "./RolesPicker";
import { EmpresaFormPanel } from "./EmpresaFormPanel";

export type VinculoEmpresa = {
  id: string;
  empresa_id: string;
  roles: RolEmpresa[];
  observaciones: string | null;
};

type Lote = Record<string, { marcada: boolean; rol: RolPersona | "" }>;

// Estable entre renders: el <Buscador /> la usa como dependencia del efecto
// que carga la primera tanda.
const buscarEmpresas = (texto: string) => buscarEmpresasParaVincular(texto);

export function VincularEmpresaPanel({
  obraId,
  vinculo,
  puedeCrearEmpresa,
  onClose,
}: {
  obraId: string;
  vinculo?: VinculoEmpresa;
  puedeCrearEmpresa: boolean;
  onClose: () => void;
}) {
  const [empresaId, setEmpresaId] = useState(vinculo?.empresa_id ?? "");
  const [empresaNombre, setEmpresaNombre] = useState("");
  const [roles, setRoles] = useState<RolEmpresa[]>(vinculo?.roles ?? []);
  const [observaciones, setObservaciones] = useState(vinculo?.observaciones ?? "");
  const [gente, setGente] = useState<PersonaDeEmpresa[]>([]);
  const [lote, setLote] = useState<Lote>({});
  const [enviando, setEnviando] = useState(false);
  const [error, setError] = useState<string>();
  const [creandoEmpresa, setCreandoEmpresa] = useState(false);

  // Al elegir la empresa se trae su gente y viene toda tildada: es lo que pidió
  // el usuario. Las que ya están en la obra vienen destildadas porque volver a
  // agregarlas no hace nada — la función las saltea con ON CONFLICT.
  async function elegirEmpresa(id: string, nombre: string) {
    setEmpresaId(id);
    setEmpresaNombre(nombre);

    const personas = await personasDeEmpresa(id, obraId);
    setGente(personas);
    setLote(
      Object.fromEntries(
        personas.map((p) => [p.persona_id, { marcada: !p.ya_en_obra, rol: "" as const }]),
      ),
    );
  }

  function cambiar(personaId: string, cambio: Partial<Lote[string]>) {
    setLote((prev) => ({ ...prev, [personaId]: { ...prev[personaId], ...cambio } }));
  }

  function rolParaTodas(rol: RolPersona | "") {
    setLote((prev) =>
      Object.fromEntries(Object.entries(prev).map(([id, f]) => [id, { ...f, rol }])),
    );
  }

  async function guardar() {
    if (!empresaId) return setError("Elegí una empresa");
    if (roles.length === 0) return setError("Elegí al menos un rol");

    const marcadas = gente.filter((p) => lote[p.persona_id]?.marcada);
    const sinRol = marcadas.filter((p) => !lote[p.persona_id]?.rol);
    if (sinRol.length > 0) {
      return setError(
        `Elegí el rol en la obra de ${sinRol.map((p) => p.nombre).join(", ")}, o destildalas`,
      );
    }

    setError(undefined);
    setEnviando(true);

    if (vinculo) {
      const result = await editarVinculoEmpresa(vinculo.id, {
        obra_id: obraId,
        empresa_id: empresaId,
        roles,
        observaciones,
        personas: [],
      });
      setEnviando(false);
      if (!result.success) return toast.error(result.error);
      toast.success("Vínculo actualizado");
      return onClose();
    }

    const result = await vincularEmpresa({
      obra_id: obraId,
      empresa_id: empresaId,
      roles,
      observaciones,
      personas: marcadas.map((p) => ({
        persona_id: p.persona_id,
        roles: [lote[p.persona_id].rol as RolPersona],
      })),
    });
    setEnviando(false);

    if (!result.success) return toast.error(result.error);

    const partes = [
      result.pendiente ? "Empresa vinculada, pendiente de autorización" : "Empresa vinculada",
    ];
    if (result.personas > 0) {
      partes.push(
        `${result.personas} ${result.personas === 1 ? "persona agregada" : "personas agregadas"}`,
      );
    }
    if (result.personasPendientes > 0) {
      partes.push(`${result.personasPendientes} esperando autorización`);
    }

    const mensaje = partes.join(" · ");
    if (result.pendiente || result.personasPendientes > 0) toast.warning(mensaje);
    else toast.success(mensaje);
    onClose();
  }

  return (
    <>
      <RightPanel
        title={vinculo ? "Modificar vínculo" : "Vincular empresa"}
        subtitle={empresaNombre || undefined}
        onClose={onClose}
        hayCambios={roles.length > 0 || !!empresaId}
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
              <label className="t-label t-label-req mb-1 block">Empresa</label>
              {empresaId ? (
                <div className="flex items-center gap-2">
                  <span className="t-body-m flex-1 font-semibold">{empresaNombre}</span>
                  <button
                    type="button"
                    className="btn btn-ghost btn-sm"
                    onClick={() => {
                      setEmpresaId("");
                      setEmpresaNombre("");
                      setGente([]);
                      setLote({});
                    }}
                  >
                    Cambiar
                  </button>
                </div>
              ) : (
                <>
                  <Buscador
                    placeholder="Buscar empresa…"
                    buscar={buscarEmpresas}
                    onElegir={(o) => elegirEmpresa(o.id, o.etiqueta)}
                  />
                  {puedeCrearEmpresa && (
                    <button
                      type="button"
                      className="btn btn-secondary btn-sm mt-2"
                      onClick={() => setCreandoEmpresa(true)}
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
            <label className="t-label t-label-req mb-1 block">Roles en esta obra</label>
            {/* Una sola relación con varios roles: constructora y
                desarrolladora de la misma obra no son dos vínculos. */}
            <RolesPicker
              opciones={ROLES_EMPRESA}
              labels={LABEL_ROL_EMPRESA}
              seleccionados={roles}
              onChange={setRoles}
              error={error}
            />
          </div>

          {!vinculo && gente.length > 0 && (
            <div>
              <div className="mb-1 flex flex-wrap items-center gap-2">
                <label className="t-label flex-1">Gente de esta empresa</label>
                <select
                  className="input w-auto"
                  defaultValue=""
                  aria-label="Rol para todas las tildadas"
                  onChange={(e) => rolParaTodas(e.target.value as RolPersona | "")}
                >
                  <option value="">Rol para todas…</option>
                  {ROLES_PERSONA.map((r) => (
                    <option key={r} value={r}>
                      {LABEL_ROL_PERSONA[r]}
                    </option>
                  ))}
                </select>
              </div>
              <p className="t-caption mb-2">
                Vienen todas tildadas. El rol es de esta obra, no el cargo en la empresa.
              </p>

              <ul className="flex flex-col gap-2">
                {gente.map((p) => {
                  const fila = lote[p.persona_id];
                  return (
                    <li
                      key={p.persona_id}
                      className="card flex flex-wrap items-center gap-x-3 gap-y-2 p-3"
                    >
                      <label className="tap-target flex min-w-0 flex-1 cursor-pointer items-center gap-2">
                        <input
                          type="checkbox"
                          className="h-4 w-4 shrink-0 accent-brand-700"
                          checked={fila?.marcada ?? false}
                          disabled={p.ya_en_obra}
                          onChange={(e) => cambiar(p.persona_id, { marcada: e.target.checked })}
                        />
                        <span className="t-body-m min-w-0 truncate font-semibold">
                          {p.nombre} {p.apellido ?? ""}
                        </span>
                      </label>
                      {p.cargo && <span className="t-caption">{p.cargo}</span>}
                      {p.ya_en_obra && <span className="badge badge-neutral">Ya está en la obra</span>}
                      {!p.es_mia && !p.ya_en_obra && (
                        <span className="badge badge-warning">Necesita autorización</span>
                      )}
                      {!p.ya_en_obra && (
                        <select
                          className="input w-auto"
                          value={fila?.rol ?? ""}
                          aria-label={`Rol de ${p.nombre} en esta obra`}
                          onChange={(e) =>
                            cambiar(p.persona_id, { rol: e.target.value as RolPersona | "" })
                          }
                        >
                          <option value="">Rol…</option>
                          {ROLES_PERSONA.map((r) => (
                            <option key={r} value={r}>
                              {LABEL_ROL_PERSONA[r]}
                            </option>
                          ))}
                        </select>
                      )}
                    </li>
                  );
                })}
              </ul>
            </div>
          )}

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

      {creandoEmpresa && (
        <EmpresaFormPanel
          onClose={() => setCreandoEmpresa(false)}
          onCreada={(id, pendiente, nombre) => {
            // Una empresa congelada no se puede vincular todavía: el trigger
            // corta con OB012 y el panel quedaría prometiendo algo que falla.
            if (!pendiente) elegirEmpresa(id, nombre);
          }}
        />
      )}
    </>
  );
}
