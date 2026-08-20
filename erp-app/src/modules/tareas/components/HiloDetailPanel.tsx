"use client";

import { useState } from "react";
import { toast } from "sonner";
import { Archive, CheckCircle2, Clock, ListPlus, Pencil, Plus, Undo2, UserRound } from "lucide-react";
import { RightPanel } from "@/components/ui/RightPanel";
import { OverflowMenu } from "@/components/ui/OverflowMenu";
import { ConfirmModal } from "@/components/ui/Modal";
import { desactivarHilo } from "../actions";
import type { TareaConAsignados, TareaHilo, TareaPlantilla, TareaProyecto, Usuario } from "../types";
import { TareaCard } from "./TareaCard";
import { TareaFormPanel } from "./TareaFormPanel";
import { HiloFormPanel } from "./HiloFormPanel";
import { PosponerPanel } from "./PosponerPanel";
import { UsarPlantillaPanel } from "./UsarPlantillaPanel";
import { CerrarHiloModal } from "./CerrarHiloModal";
import { DeshacerConversionModal } from "./DeshacerConversionModal";
import { NotasSection } from "./NotasSection";
import { MetricasResumen, contarCompletadas } from "./MetricasResumen";
import { useOrdenTemperatura } from "../useOrdenTemperatura";

// Contenido que antes vivía inline en HiloCard (expandido) — spec pedida:
// la vista Lista no muestra tareas/acciones del hilo, solo en este panel.
export function HiloDetailPanel({
  hilo,
  tareasDelHilo,
  proyecto,
  proyectos,
  usuarios,
  plantillas,
  miembrosPorProyecto,
  usuarioActualId,
  gestionarAjenas,
  puedeAsignar,
  relacionCon,
  onClose,
}: {
  hilo: TareaHilo;
  tareasDelHilo: TareaConAsignados[];
  proyecto: TareaProyecto | null;
  proyectos: TareaProyecto[];
  usuarios: Usuario[];
  plantillas: TareaPlantilla[];
  miembrosPorProyecto: Record<string, string[]>;
  usuarioActualId: string | null;
  gestionarAjenas: boolean;
  puedeAsignar: boolean;
  relacionCon?: string | null;
  onClose: () => void;
}) {
  const [agregandoTarea, setAgregandoTarea] = useState(false);
  const [editando, setEditando] = useState(false);
  const [posponiendo, setPosponiendo] = useState(false);
  const [usandoPlantilla, setUsandoPlantilla] = useState(false);
  const [deshaciendo, setDeshaciendo] = useState(false);
  const [cerrandoManual, setCerrandoManual] = useState(false);
  const [desactivando, setDesactivando] = useState(false);
  const { ordenar, onTemperaturaChange } = useOrdenTemperatura();

  // Sin creado_por: crear un hilo no da autoridad sobre él, la da ser su
  // responsable. Mostrar acciones que la RLS después descarta en silencio
  // (un UPDATE denegado afecta 0 filas, no tira error) es peor que ocultarlas.
  const puedeGestionar = gestionarAjenas || hilo.responsable_id === usuarioActualId;

  // Las tareas del hilo heredan su proyecto: quiénes pueden recibirlas sale
  // de los miembros de ese proyecto.
  const miembros = proyecto ? (miembrosPorProyecto[proyecto.id] ?? []) : null;
  const responsable = usuarios.find((u) => u.id === hilo.responsable_id)?.nombre ?? null;
  const completadas = contarCompletadas(tareasDelHilo);

  async function onDesactivar() {
    const result = await desactivarHilo(hilo.id);
    if (!result.success) toast.error(result.error);
    else onClose();
  }

  return (
    <RightPanel title={hilo.titulo} subtitle={proyecto?.nombre} onClose={onClose}>
      <div className="flex min-h-0 flex-1 flex-col overflow-y-auto">
        <div className="flex flex-wrap items-center gap-2 border-b border-border p-[13px] px-5">
          <button className="btn btn-ghost btn-sm" onClick={() => setAgregandoTarea(true)}>
            <Plus size={14} strokeWidth={1.75} />
            Agregar tarea
          </button>
          {puedeGestionar && (
            <button className="btn btn-ghost btn-sm" onClick={() => setEditando(true)}>
              <Pencil size={14} strokeWidth={1.75} />
              Modificar hilo
            </button>
          )}
          {(plantillas.length > 0 || puedeGestionar) && (
            <OverflowMenu
              items={[
                ...(plantillas.length > 0
                  ? [
                      {
                        label: "Usar plantilla",
                        icon: <ListPlus size={14} strokeWidth={1.75} />,
                        onClick: () => setUsandoPlantilla(true),
                      },
                    ]
                  : []),
                ...(puedeGestionar
                  ? [
                      ...(hilo.estado === "abierto"
                        ? [
                            {
                              label: "Cerrar hilo",
                              icon: <CheckCircle2 size={14} strokeWidth={1.75} />,
                              onClick: () => setCerrandoManual(true),
                            },
                          ]
                        : []),
                      { label: "Posponer", icon: <Clock size={14} strokeWidth={1.75} />, onClick: () => setPosponiendo(true) },
                      {
                        label: "Deshacer conversión",
                        icon: <Undo2 size={14} strokeWidth={1.75} />,
                        onClick: () => setDeshaciendo(true),
                      },
                      {
                        label: "Desactivar",
                        icon: <Archive size={14} strokeWidth={1.75} />,
                        onClick: () => setDesactivando(true),
                        destructive: true,
                      },
                    ]
                  : []),
              ]}
            />
          )}
        </div>

        <div className="flex flex-col gap-2 border-b border-border p-[13px] px-5">
          {hilo.descripcion && <p className="t-body-m whitespace-pre-wrap">{hilo.descripcion}</p>}
          <div className="t-caption flex flex-wrap items-center gap-3">
            {responsable && (
              <span className="flex items-center gap-1" title="Dueño del hilo">
                <UserRound size={13} strokeWidth={1.75} />
                {responsable}
              </span>
            )}
            <span>
              {completadas}/{tareasDelHilo.length} completadas
            </span>
            <MetricasResumen createdAt={hilo.created_at} tareas={tareasDelHilo} />
          </div>
        </div>

        {tareasDelHilo.length === 0 ? (
          <p className="t-caption px-5 py-3">Sin tareas todavía.</p>
        ) : (
          <div className="flex flex-col gap-3 p-[13px] px-5">
            {ordenar(tareasDelHilo).map((t) => (
              <TareaCard
                key={t.id}
                tarea={t}
                usuarios={usuarios}
                proyectos={proyectos}
                miembrosPorProyecto={miembrosPorProyecto}
                proyectoHeredadoId={proyecto?.id ?? null}
                usuarioActualId={usuarioActualId}
                gestionarAjenas={gestionarAjenas}
                puedeAsignar={puedeAsignar}
                relacionCon={relacionCon}
                onTemperaturaChange={onTemperaturaChange}
              />
            ))}
          </div>
        )}

        <div className="border-t border-border p-[13px] px-5">
          <p className="t-label mb-2">Notas del hilo</p>
          <NotasSection tipo="hilo" id={hilo.id} puedeAgregar={puedeGestionar} />
        </div>
      </div>

      {agregandoTarea && (
        <TareaFormPanel
          usuarios={usuarios}
          proyectos={proyectos}
          miembrosPorProyecto={miembrosPorProyecto}
          usuarioActualId={usuarioActualId}
          puedeAsignar={puedeAsignar}
          hiloId={hilo.id}
          proyectoHeredadoId={proyecto?.id ?? null}
          onClose={() => setAgregandoTarea(false)}
        />
      )}
      {editando && (
        <HiloFormPanel
          usuarios={usuarios}
          proyectos={proyectos}
          miembrosPorProyecto={miembrosPorProyecto}
          usuarioActualId={usuarioActualId}
          puedeAsignar={puedeAsignar}
          hilo={hilo}
          onClose={() => setEditando(false)}
        />
      )}
      {posponiendo && (
        <PosponerPanel tipo="hilo" id={hilo.id} titulo={hilo.titulo} onClose={() => setPosponiendo(false)} />
      )}
      {usandoPlantilla && (
        <UsarPlantillaPanel
          hiloId={hilo.id}
          plantillas={plantillas}
          usuarios={usuarios}
          miembros={miembros}
          usuarioActualId={usuarioActualId}
          puedeAsignar={puedeAsignar}
          onClose={() => setUsandoPlantilla(false)}
        />
      )}
      {deshaciendo && (
        <DeshacerConversionModal
          hiloId={hilo.id}
          hiloTitulo={hilo.titulo}
          tareas={tareasDelHilo}
          onClose={() => setDeshaciendo(false)}
        />
      )}
      {cerrandoManual && (
        <CerrarHiloModal
          hiloId={hilo.id}
          hiloTitulo={hilo.titulo}
          tareas={tareasDelHilo}
          onClose={() => setCerrandoManual(false)}
          onMantenerAbierto={() => setCerrandoManual(false)}
        />
      )}
      {desactivando && (
        <ConfirmModal
          title="Desactivar hilo"
          mensaje={`¿Desactivar el hilo "${hilo.titulo}"?`}
          onConfirm={onDesactivar}
          onClose={() => setDesactivando(false)}
        />
      )}
    </RightPanel>
  );
}
