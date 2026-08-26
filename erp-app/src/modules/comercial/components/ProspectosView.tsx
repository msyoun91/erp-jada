"use client";

import { useState } from "react";
import { Archive, Pencil, Target } from "lucide-react";
import { toast } from "sonner";
import type { UsuarioBasico } from "@/lib/usuarios";
import { ConfirmModal } from "@/components/ui/Modal";
import { OverflowMenu } from "@/components/ui/OverflowMenu";
import { Paginacion, usePaginado } from "@/components/ui/Paginacion";
import { SearchInput } from "@/components/ui/SearchInput";
import { formatFecha } from "@/lib/utils";
import { desactivarProspecto } from "../actions";
import {
  ESTADOS_PROSPECTO,
  type Empresa,
  type Fuente,
  type ObraConRelaciones,
  type PersonaConEmpresa,
  type ProspectoListado,
} from "../types";
import {
  empresaPrincipal,
  ESTADO_OBRA_LABEL,
  ESTADO_PROSPECTO_BADGE,
  ESTADO_PROSPECTO_LABEL,
  formatMonto,
  formatPorcentaje,
  nombreEmpresa,
  nombrePersona,
  normalizar,
  referente,
} from "./comercialLabels";
import { ProspectoDetailPanel } from "./ProspectoDetailPanel";
import { ProspectoFormPanel } from "./ProspectoFormPanel";

export function ProspectosView({
  prospectos,
  obras,
  empresas,
  personas,
  fuentes,
  usuarios,
  usuarioActualId,
  puedeGestionar,
  gestionarAjenos,
  gestionarObras,
  verComision,
}: {
  prospectos: ProspectoListado[];
  obras: ObraConRelaciones[];
  empresas: Empresa[];
  personas: PersonaConEmpresa[];
  fuentes: Fuente[];
  usuarios: UsuarioBasico[];
  usuarioActualId: string | null;
  puedeGestionar: boolean;
  gestionarAjenos: boolean;
  gestionarObras: boolean;
  verComision: boolean;
}) {
  const [texto, setTexto] = useState("");
  const [estado, setEstado] = useState("");
  const [creando, setCreando] = useState(false);
  const [editando, setEditando] = useState<ProspectoListado | null>(null);
  const [abierto, setAbierto] = useState<ProspectoListado | null>(null);
  const [desactivando, setDesactivando] = useState<ProspectoListado | null>(null);

  async function onDesactivar(prospecto: ProspectoListado) {
    const result = await desactivarProspecto(prospecto.id);
    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success("Prospecto desactivado");
  }

  const q = normalizar(texto);
  const filtrados = prospectos.filter((p) => {
    if (estado && p.estado_prospecto !== estado) return false;
    const obra = p.obras;
    return (
      normalizar(obra?.nombre ?? "").includes(q) ||
      normalizar(obra?.localidad ?? "").includes(q) ||
      normalizar(p.usuarios?.nombre ?? "").includes(q)
    );
  });
  const { visibles, ...paginado } = usePaginado(filtrados);

  const prospectoAbierto = abierto
    ? (prospectos.find((p) => p.id === abierto.id) ?? null)
    : null;

  return (
    <div>
      <div className="mb-4 flex flex-wrap items-center gap-3">
        <SearchInput
          value={texto}
          onChange={setTexto}
          placeholder="Buscar por obra, localidad o responsable…"
        />
        <select
          className="input w-auto py-1.5"
          value={estado}
          onChange={(e) => setEstado(e.target.value)}
          aria-label="Filtrar por estado"
        >
          <option value="">Todos los estados</option>
          {ESTADOS_PROSPECTO.map((e) => (
            <option key={e} value={e}>
              {ESTADO_PROSPECTO_LABEL[e]}
            </option>
          ))}
        </select>
        {puedeGestionar && (
          <button className="btn btn-primary" onClick={() => setCreando(true)}>
            <Target size={16} />
            Nuevo prospecto
          </button>
        )}
      </div>

      <Paginacion {...paginado} etiqueta="prospectos" />

      {filtrados.length === 0 ? (
        <div className="empty-state">
          <p className="t-h3">
            {texto || estado ? "Sin resultados" : "Sin prospectos todavía"}
          </p>
          <p className="t-body-m mt-1">
            {texto || estado
              ? "Probá con otro filtro."
              : "Cargá una obra en la pestaña Obras y después creá su prospecto."}
          </p>
        </div>
      ) : (
        <div className="flex flex-col rounded-lg border border-border bg-bg-surface">
          {visibles.map((prospecto) => {
            const obra = prospecto.obras;
            const principal = obra ? empresaPrincipal(obra.obra_empresa) : null;
            const quienRefirio = obra ? referente(obra.obra_persona) : null;
            const comision = quienRefirio?.comercial_comisiones.find((c) => c.activo);

            return (
              <div
                key={prospecto.id}
                className="flex items-center gap-2 border-b border-border row last:border-b-0"
              >
                <button
                  className="min-w-0 flex-1 text-left"
                  onClick={() => setAbierto(prospecto)}
                  aria-label={`Ver ${obra?.nombre ?? "prospecto"}`}
                >
                  <p className="t-body-m truncate font-medium text-text-primary">
                    {obra?.nombre ?? "Obra sin nombre"}
                  </p>
                  <p className="t-caption truncate">
                    {[
                      obra?.localidad,
                      obra && ESTADO_OBRA_LABEL[obra.estado_obra],
                      principal && nombreEmpresa(principal.empresas),
                      quienRefirio &&
                        `Ref. ${nombrePersona(quienRefirio.personas)}${
                          verComision && comision
                            ? ` (${formatPorcentaje(comision.porcentaje)})`
                            : ""
                        }`,
                      prospecto.comercial_fuentes?.nombre,
                    ]
                      .filter(Boolean)
                      .join(" · ")}
                  </p>
                  <p className="t-caption truncate">
                    {[
                      formatMonto(prospecto.potencial_estimado, prospecto.moneda_potencial),
                      prospecto.fecha_estimada_compra &&
                        `Compra ${formatFecha(prospecto.fecha_estimada_compra)}`,
                      prospecto.usuarios?.nombre,
                    ]
                      .filter(Boolean)
                      .join(" · ")}
                  </p>
                </button>

                <span
                  className={`badge shrink-0 ${ESTADO_PROSPECTO_BADGE[prospecto.estado_prospecto]}`}
                >
                  {ESTADO_PROSPECTO_LABEL[prospecto.estado_prospecto]}
                </span>

                {puedeGestionar && (
                  <OverflowMenu
                    items={[
                      {
                        label: "Modificar",
                        icon: <Pencil size={14} strokeWidth={1.75} />,
                        onClick: () => setEditando(prospecto),
                      },
                      {
                        label: "Desactivar",
                        icon: <Archive size={14} strokeWidth={1.75} />,
                        onClick: () => setDesactivando(prospecto),
                        destructive: true,
                      },
                    ]}
                  />
                )}
              </div>
            );
          })}
        </div>
      )}

      {(creando || editando) && (
        <ProspectoFormPanel
          prospecto={editando ?? undefined}
          obras={obras}
          obrasConProspecto={prospectos.map((p) => p.obra_id)}
          fuentes={fuentes}
          usuarios={usuarios}
          usuarioActualId={usuarioActualId}
          gestionarAjenos={gestionarAjenos}
          onClose={() => {
            setCreando(false);
            setEditando(null);
          }}
        />
      )}

      {prospectoAbierto && (
        <ProspectoDetailPanel
          prospecto={prospectoAbierto}
          empresas={empresas}
          personas={personas}
          gestionarObras={gestionarObras}
          verComision={verComision}
          onClose={() => setAbierto(null)}
        />
      )}

      {desactivando && (
        <ConfirmModal
          title="Desactivar prospecto"
          mensaje={`¿Desactivar el prospecto de ${desactivando.obras?.nombre ?? "esta obra"}? La obra y sus relaciones no se tocan.`}
          onConfirm={() => onDesactivar(desactivando)}
          onClose={() => setDesactivando(null)}
        />
      )}
    </div>
  );
}
