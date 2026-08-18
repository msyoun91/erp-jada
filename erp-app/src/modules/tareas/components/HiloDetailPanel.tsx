"use client";

import { useState } from "react";
import { toast } from "sonner";
import { Archive, CheckCircle2, Clock, ListPlus, Plus, Undo2 } from "lucide-react";
import { RightPanel } from "@/components/ui/RightPanel";
import { OverflowMenu } from "@/components/ui/OverflowMenu";
import { ConfirmModal } from "@/components/ui/Modal";
import { desactivarHilo } from "../actions";
import type { TareaConAsignados, TareaHilo, TareaPlantilla, TareaProyecto, Usuario } from "../types";
import { TareaRow } from "./TareaRow";
import { TareaFormPanel } from "./TareaFormPanel";
import { PosponerPanel } from "./PosponerPanel";
import { UsarPlantillaPanel } from "./UsarPlantillaPanel";
import { CerrarHiloModal } from "./CerrarHiloModal";
import { DeshacerConversionModal } from "./DeshacerConversionModal";
import { NotasSection } from "./NotasSection";
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
  usuarioActualId,
  gestionarAjenas,
  onClose,
}: {
  hilo: TareaHilo;
  tareasDelHilo: TareaConAsignados[];
  proyecto: TareaProyecto | null;
  proyectos: TareaProyecto[];
  usuarios: Usuario[];
  plantillas: TareaPlantilla[];
  usuarioActualId: string | null;
  gestionarAjenas: boolean;
  onClose: () => void;
}) {
  const [agregandoTarea, setAgregandoTarea] = useState(false);
  const [posponiendo, setPosponiendo] = useState(false);
  const [usandoPlantilla, setUsandoPlantilla] = useState(false);
  const [deshaciendo, setDeshaciendo] = useState(false);
  const [cerrandoManual, setCerrandoManual] = useState(false);
  const [desactivando, setDesactivando] = useState(false);
  const { ordenar, onTemperaturaChange } = useOrdenTemperatura();

  const puedeGestionar =
    gestionarAjenas || hilo.creado_por === usuarioActualId || hilo.responsable_id === usuarioActualId;

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

        {tareasDelHilo.length === 0 ? (
          <p className="t-caption px-5 py-3">Sin tareas todavía.</p>
        ) : (
          <div className="flex flex-col">
            {ordenar(tareasDelHilo).map((t) => (
              <div key={t.id} className="border-b border-border last:border-b-0">
                <TareaRow
                  tarea={t}
                  usuarios={usuarios}
                  proyectos={proyectos}
                  usuarioActualId={usuarioActualId}
                  gestionarAjenas={gestionarAjenas}
                  onTemperaturaChange={onTemperaturaChange}
                />
              </div>
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
          usuarioActualId={usuarioActualId}
          hiloId={hilo.id}
          onClose={() => setAgregandoTarea(false)}
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
          usuarioActualId={usuarioActualId}
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
