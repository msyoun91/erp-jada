"use client";

import { useState } from "react";
import { Archive, Pencil, UserPlus } from "lucide-react";
import { toast } from "sonner";
import { ConfirmModal } from "@/components/ui/Modal";
import { OverflowMenu } from "@/components/ui/OverflowMenu";
import { Paginacion, usePaginado } from "@/components/ui/Paginacion";
import { SearchInput } from "@/components/ui/SearchInput";
import { desactivarPersona } from "../actions";
import type { Empresa, PersonaConEmpresa } from "../types";
import { PersonaFormPanel } from "./PersonaFormPanel";
import { nombreEmpresa, nombrePersona, normalizar } from "./comercialLabels";

export function PersonasView({
  personas,
  empresas,
  puedeGestionar,
}: {
  personas: PersonaConEmpresa[];
  empresas: Empresa[];
  puedeGestionar: boolean;
}) {
  const [texto, setTexto] = useState("");
  const [creando, setCreando] = useState(false);
  const [editando, setEditando] = useState<PersonaConEmpresa | null>(null);
  const [desactivando, setDesactivando] = useState<PersonaConEmpresa | null>(null);

  async function onDesactivar(persona: PersonaConEmpresa) {
    const result = await desactivarPersona(persona.id);
    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success("Persona desactivada");
  }

  const q = normalizar(texto);
  const filtradas = personas.filter(
    (p) =>
      normalizar(nombrePersona(p)).includes(q) ||
      normalizar(p.email ?? "").includes(q) ||
      normalizar(p.cargo ?? "").includes(q) ||
      normalizar(p.empresas?.razon_social ?? "").includes(q)
  );
  const { visibles, ...paginado } = usePaginado(filtradas);

  return (
    <div>
      <div className="mb-4 flex flex-wrap items-center gap-3">
        <SearchInput
          value={texto}
          onChange={setTexto}
          placeholder="Buscar por nombre, empresa, cargo o email…"
        />
        {puedeGestionar && (
          <button className="btn btn-primary" onClick={() => setCreando(true)}>
            <UserPlus size={16} />
            Nueva persona
          </button>
        )}
      </div>

      <Paginacion {...paginado} etiqueta="personas" />

      {filtradas.length === 0 ? (
        <div className="empty-state">
          <p className="t-h3">{texto ? "Sin resultados" : "Sin personas todavía"}</p>
          <p className="t-body-m mt-1">
            {texto ? "Probá con otro término de búsqueda." : 'Cargá la primera con "Nueva persona".'}
          </p>
        </div>
      ) : (
        <div className="flex flex-col rounded-lg border border-border bg-bg-surface">
          {visibles.map((persona) => (
            <div
              key={persona.id}
              className="flex items-center gap-2 border-b border-border row last:border-b-0"
            >
              <div className="min-w-0 flex-1">
                <p className="t-body-m truncate font-medium text-text-primary">
                  {nombrePersona(persona)}
                </p>
                <p className="t-caption truncate">
                  {[
                    persona.empresas && nombreEmpresa(persona.empresas),
                    persona.cargo,
                    persona.telefono ?? persona.whatsapp,
                    persona.email,
                  ]
                    .filter(Boolean)
                    .join(" · ") || "Sin datos de contacto"}
                </p>
              </div>

              {puedeGestionar && (
                <OverflowMenu
                  items={[
                    {
                      label: "Modificar",
                      icon: <Pencil size={14} strokeWidth={1.75} />,
                      onClick: () => setEditando(persona),
                    },
                    {
                      label: "Desactivar",
                      icon: <Archive size={14} strokeWidth={1.75} />,
                      onClick: () => setDesactivando(persona),
                      destructive: true,
                    },
                  ]}
                />
              )}
            </div>
          ))}
        </div>
      )}

      {creando && (
        <PersonaFormPanel
          personas={personas}
          empresas={empresas}
          onClose={() => setCreando(false)}
        />
      )}

      {editando && (
        <PersonaFormPanel
          persona={editando}
          personas={personas}
          empresas={empresas}
          onClose={() => setEditando(null)}
        />
      )}

      {desactivando && (
        <ConfirmModal
          title="Desactivar persona"
          mensaje={`¿Desactivar a ${nombrePersona(desactivando)}? Si participa en alguna obra hay que sacarla de esa obra primero.`}
          onConfirm={() => onDesactivar(desactivando)}
          onClose={() => setDesactivando(null)}
        />
      )}
    </div>
  );
}
