"use client";

import { useState } from "react";
import { toast } from "sonner";
import {
  Archive,
  ArrowRightLeft,
  CalendarClock,
  Clock,
  ExternalLink,
  GitBranch,
  Lock,
  MessageSquare,
  Repeat,
  Thermometer,
  Unlink,
  UserCog,
} from "lucide-react";
import { OverflowMenu } from "@/components/ui/OverflowMenu";
import {
  actualizarTemperatura,
  asociarTareaHilo,
  cambiarEstadoTarea,
  desactivarTarea,
  desasociarTareaHilo,
} from "../actions";
import type { TareaConAsignados, TareaHilo, Usuario } from "../types";
import { diasEntreISO, hoyISO } from "@/lib/utils";
import { ReasignarPanel } from "./ReasignarPanel";
import { PosponerPanel } from "./PosponerPanel";
import { CompletarModal } from "./CompletarModal";
import { AgregarPasoPanel } from "./AgregarPasoPanel";
import { NotasSection } from "./NotasSection";

const ESTADO_LABEL: Record<string, string> = {
  pendiente: "Pendiente",
  en_progreso: "En progreso",
  completada: "Completada",
  cancelada: "Cancelada",
};

const ESTADO_BADGE: Record<string, string> = {
  pendiente: "badge-neutral",
  en_progreso: "badge-info",
  completada: "badge-success",
  cancelada: "badge-error",
};

const RECURRENCIA_LABEL: Record<string, string> = { dia: "día(s)", mes: "mes(es)" };

// Umbrales fijos — spec pide "configurable" pero no hay un segundo caso real
// todavía que justifique una UI de settings para esto (simplicidad antes que
// abstracción). Ajustar acá si en el futuro se necesita por tipo de tarea.
const PROXIMA_DIAS = 3;
const ANTIGUEDAD_AMBAR_DIAS = 14;
const ANTIGUEDAD_ROJO_DIAS = 30;

function iniciales(nombre: string) {
  const parts = nombre.trim().split(" ");
  if (parts.length >= 2) return (parts[0][0] + parts[1][0]).toUpperCase();
  return nombre.slice(0, 2).toUpperCase();
}

export function TareaRow({
  tarea,
  usuarios,
  hilosDisponibles,
  usuarioActualId,
  gestionarAjenas,
  onTemperaturaChange,
}: {
  tarea: TareaConAsignados;
  usuarios: Usuario[];
  hilosDisponibles?: TareaHilo[];
  usuarioActualId: string | null;
  gestionarAjenas: boolean;
  onTemperaturaChange?: (id: string, temperatura: number) => void;
}) {
  const [estadoBase, setEstadoBase] = useState(tarea.estado);
  const [estadoLocal, setEstadoLocal] = useState(tarea.estado);
  if (tarea.estado !== estadoBase) {
    setEstadoBase(tarea.estado);
    setEstadoLocal(tarea.estado);
  }

  const [tempBase, setTempBase] = useState(tarea.temperatura);
  const [tempLocal, setTempLocal] = useState(tarea.temperatura);
  if (tarea.temperatura !== tempBase) {
    setTempBase(tarea.temperatura);
    setTempLocal(tarea.temperatura);
  }

  const [reasignando, setReasignando] = useState(false);
  const [posponiendo, setPosponiendo] = useState(false);
  const [completando, setCompletando] = useState(false);
  const [agregandoPaso, setAgregandoPaso] = useState(false);
  const [mostrandoNotas, setMostrandoNotas] = useState(false);
  const [mostrandoMoverHilo, setMostrandoMoverHilo] = useState(false);

  const asignadosActivos = tarea.tareas_asignados.filter((a) => a.activo);
  const esAsignado =
    gestionarAjenas ||
    tarea.creado_por === usuarioActualId ||
    tarea.responsable_id === usuarioActualId ||
    asignadosActivos.some((a) => a.usuario_id === usuarioActualId);
  const puedeGestionar =
    gestionarAjenas || tarea.creado_por === usuarioActualId || tarea.responsable_id === usuarioActualId;

  const activa = estadoLocal !== "completada" && estadoLocal !== "cancelada";
  const diasVencimiento = tarea.fecha_vencimiento ? diasEntreISO(hoyISO(), tarea.fecha_vencimiento) : null;
  const vencida = activa && diasVencimiento !== null && diasVencimiento < 0;
  const proximaAVencer = activa && diasVencimiento !== null && diasVencimiento >= 0 && diasVencimiento <= PROXIMA_DIAS;
  const fechaClase = vencida ? "text-error" : proximaAVencer ? "text-warning" : "";

  const diasAntiguedad = !tarea.fecha_vencimiento ? diasEntreISO(tarea.created_at.slice(0, 10), hoyISO()) : null;
  const antiguedadClase =
    diasAntiguedad === null
      ? ""
      : diasAntiguedad >= ANTIGUEDAD_ROJO_DIAS
        ? "text-error"
        : diasAntiguedad >= ANTIGUEDAD_AMBAR_DIAS
          ? "text-warning"
          : "";

  async function cambiarEstado(nuevo: "pendiente" | "en_progreso" | "cancelada") {
    const anterior = estadoLocal;
    setEstadoLocal(nuevo);
    const result = await cambiarEstadoTarea(tarea.id, nuevo);
    if (!result.success) {
      setEstadoLocal(anterior);
      toast.error(result.error);
    }
  }

  async function commitTemperatura() {
    if (tempLocal === tarea.temperatura) return;
    const result = await actualizarTemperatura(tarea.id, tempLocal);
    if (!result.success) {
      setTempLocal(tarea.temperatura);
      toast.error(result.error);
    }
  }

  async function moverAHilo(hiloId: string) {
    if (!hiloId) return;
    const result = await asociarTareaHilo(tarea.id, hiloId);
    if (!result.success) toast.error(result.error);
  }

  async function quitarDeHilo() {
    const result = await desasociarTareaHilo(tarea.id);
    if (!result.success) toast.error(result.error);
  }

  async function desactivar() {
    if (!confirm(`¿Desactivar "${tarea.titulo}"?`)) return;
    const result = await desactivarTarea(tarea.id);
    if (!result.success) toast.error(result.error);
  }

  return (
    <div className="p-[13px] px-5">
      <div className="flex flex-wrap items-center gap-2">
        {tarea.visibilidad === "privado" && (
          <Lock size={13} strokeWidth={1.75} className="shrink-0 text-text-tertiary" title="Privada" />
        )}
        {tarea.recurrencia_cantidad != null && (
          <Repeat
            size={13}
            strokeWidth={1.75}
            className="shrink-0 text-text-tertiary"
            title={`Se repite cada ${tarea.recurrencia_cantidad} ${RECURRENCIA_LABEL[tarea.recurrencia_unidad ?? "dia"]}`}
          />
        )}
        {tarea.origen_app && (
          <ExternalLink
            size={13}
            strokeWidth={1.75}
            className="shrink-0 text-text-tertiary"
            title={`Vinculada a ${tarea.origen_app}`}
          />
        )}
        {tarea.posponer_hasta && (
          <Clock
            size={13}
            strokeWidth={1.75}
            className="shrink-0 text-warning"
            title={`Pospuesta hasta ${tarea.posponer_hasta}`}
          />
        )}
        <p className="t-body-m font-medium text-text-primary">{tarea.titulo}</p>
        <span className={`badge ${ESTADO_BADGE[estadoLocal]}`}>{ESTADO_LABEL[estadoLocal]}</span>
      </div>

      {tarea.descripcion && <p className="t-caption mt-1">{tarea.descripcion}</p>}

      <div className="mt-2 flex flex-wrap items-center gap-3 t-caption">
        {tarea.fecha_vencimiento ? (
          <span className={`flex items-center gap-1 ${fechaClase}`}>
            <CalendarClock size={13} strokeWidth={1.75} />
            {tarea.fecha_vencimiento}
          </span>
        ) : (
          <span className={`flex items-center gap-1 ${antiguedadClase}`}>
            <CalendarClock size={13} strokeWidth={1.75} />
            Creada hace {diasAntiguedad} {diasAntiguedad === 1 ? "día" : "días"}
          </span>
        )}
        <span className="flex items-center gap-1">
          <Thermometer size={13} strokeWidth={1.75} />
          {tempLocal}
        </span>
        {asignadosActivos.length > 0 && (
          <span className="flex items-center">
            {asignadosActivos.map((a, i) => (
              <span
                key={a.usuario_id}
                title={a.usuarios?.nombre ?? ""}
                style={{ marginLeft: i === 0 ? 0 : -6, zIndex: asignadosActivos.length - i }}
                className={`flex h-5 w-5 items-center justify-center rounded-full bg-brand-50 text-[10px] font-semibold text-brand-700 ring-2 ring-bg-surface ${
                  a.usuario_id === usuarioActualId ? "outline outline-2 outline-brand-700" : ""
                }`}
              >
                {a.usuarios ? iniciales(a.usuarios.nombre) : "?"}
              </span>
            ))}
          </span>
        )}
      </div>

      {(esAsignado || puedeGestionar) && (
        <div className="mt-3 flex flex-wrap items-center gap-2">
          {esAsignado && (
            <>
              {estadoLocal !== "completada" && (
                <button className="btn btn-primary btn-sm" onClick={() => setCompletando(true)}>
                  Completar
                </button>
              )}
              <select
                className="input w-auto py-1.5 text-[13px]"
                value={estadoLocal === "completada" ? "" : estadoLocal}
                onChange={(e) => cambiarEstado(e.target.value as "pendiente" | "en_progreso" | "cancelada")}
              >
                {estadoLocal === "completada" && <option value="">Completada</option>}
                <option value="pendiente">Pendiente</option>
                <option value="en_progreso">En progreso</option>
                <option value="cancelada">Cancelada</option>
              </select>
              <input
                type="range"
                min={1}
                max={100}
                value={tempLocal}
                onChange={(e) => {
                  const valor = Number(e.target.value);
                  setTempLocal(valor);
                  onTemperaturaChange?.(tarea.id, valor);
                }}
                onMouseUp={commitTemperatura}
                onTouchEnd={commitTemperatura}
                className="w-24 accent-brand-700"
                title="Temperatura"
              />
            </>
          )}

          <button className="btn btn-ghost btn-sm" onClick={() => setMostrandoNotas((v) => !v)}>
            <MessageSquare size={14} strokeWidth={1.75} />
            Notas
          </button>

          {puedeGestionar && (
            <OverflowMenu
              items={[
                { label: "Reasignar", icon: <UserCog size={14} strokeWidth={1.75} />, onClick: () => setReasignando(true) },
                { label: "Posponer", icon: <Clock size={14} strokeWidth={1.75} />, onClick: () => setPosponiendo(true) },
                ...(tarea.hilo_id
                  ? [{ label: "Quitar del hilo", icon: <Unlink size={14} strokeWidth={1.75} />, onClick: quitarDeHilo }]
                  : [
                      {
                        label: "Agregar paso",
                        icon: <GitBranch size={14} strokeWidth={1.75} />,
                        onClick: () => setAgregandoPaso(true),
                      },
                      ...(hilosDisponibles && hilosDisponibles.length > 0
                        ? [
                            {
                              label: "Mover a hilo…",
                              icon: <ArrowRightLeft size={14} strokeWidth={1.75} />,
                              onClick: () => setMostrandoMoverHilo(true),
                            },
                          ]
                        : []),
                    ]),
                { label: "Desactivar", icon: <Archive size={14} strokeWidth={1.75} />, onClick: desactivar, destructive: true },
              ]}
            />
          )}
        </div>
      )}

      {mostrandoMoverHilo && hilosDisponibles && (
        <select
          className="input mt-2 w-auto py-1.5 text-[13px]"
          value=""
          autoFocus
          onChange={(e) => {
            moverAHilo(e.target.value);
            setMostrandoMoverHilo(false);
          }}
          onBlur={() => setMostrandoMoverHilo(false)}
        >
          <option value="">Mover a hilo…</option>
          {hilosDisponibles.map((h) => (
            <option key={h.id} value={h.id}>
              {h.titulo}
            </option>
          ))}
        </select>
      )}

      {mostrandoNotas && (
        <div className="mt-3">
          <NotasSection tipo="tarea" id={tarea.id} puedeAgregar={esAsignado} />
        </div>
      )}

      {reasignando && (
        <ReasignarPanel
          tareaId={tarea.id}
          asignadosActuales={asignadosActivos.map((a) => a.usuario_id)}
          responsableActual={tarea.responsable_id}
          usuarios={usuarios}
          onClose={() => setReasignando(false)}
        />
      )}
      {posponiendo && (
        <PosponerPanel tipo="tarea" id={tarea.id} titulo={tarea.titulo} onClose={() => setPosponiendo(false)} />
      )}
      {completando && (
        <CompletarModal tareaId={tarea.id} titulo={tarea.titulo} onClose={() => setCompletando(false)} />
      )}
      {agregandoPaso && (
        <AgregarPasoPanel tareaId={tarea.id} titulo={tarea.titulo} onClose={() => setAgregandoPaso(false)} />
      )}
    </div>
  );
}
