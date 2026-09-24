"use client";

import { useState } from "react";
import Link from "next/link";
import { Archive, ArchiveRestore, ArrowLeftRight, CheckCircle2, ClipboardList, ChevronRight, Pencil, Plus, Repeat, RotateCcw, UserRound } from "lucide-react";
import { toast } from "sonner";
import { ConfirmModal } from "@/components/ui/Modal";
import { OverflowMenu } from "@/components/ui/OverflowMenu";
import { formatFecha, hoyISO } from "@/lib/utils";
import { desactivarHilo, reabrirHilo, reactivarHilo } from "../actions";
import { estaAbierto, estaBloqueado, estaEnEspera, estaVencido, ordenarPasos } from "../derivados";
import { ESTADO_HILO, ESTADO_PASO, textoRecurrencia } from "../etiquetas";
import type { HiloCompleto, PlantillaCompleta } from "../queries";
import type { Tarea } from "../types";
import { TareasProvider, useNombre, type TareasCtx } from "./contexto";
import { Historial } from "./Historial";
import { HiloFormPanel } from "./HiloFormPanel";
import { CerrarHiloModal, TransferirModal } from "./HiloModales";
import { NotasSection } from "./NotasSection";
import { PasoFormPanel } from "./PasoFormPanel";
import { PasoPanel } from "./PasoPanel";
import { UsarPlantillaPanel } from "./UsarPlantillaPanel";

type Dialogo = "sumar" | "plantilla" | "editar" | "transferir" | "cerrar" | "desactivar";

type Props = HiloCompleto & { ctx: TareasCtx; pasoAbierto: string | null; plantillas: PlantillaCompleta[] };

export function HiloView(props: Props) {
  return (
    <TareasProvider value={props.ctx}>
      <Contenido {...props} />
    </TareasProvider>
  );
}

function Contenido({ hilo, pasos, notas, ediciones, enlaces, ctx, pasoAbierto, plantillas }: Props) {
  const nombre = useNombre();
  const [dialogo, setDialogo] = useState<Dialogo | null>(null);
  const [abierto, setAbierto] = useState<string | null>(pasoAbierto);
  const hoy = hoyISO();

  const activos = pasos.filter((p) => p.activo);
  const porId = new Map(activos.map((p) => [p.id, p]));
  const conSiguiente = new Set(activos.map((p) => p.paso_anterior_id).filter((id) => id !== null));
  const ordenados = ordenarPasos(activos);
  const desactivados = pasos.filter((p) => !p.activo);
  const abiertos = activos.filter((p) => estaAbierto(p.estado)).length;

  const dueno = hilo.responsable_id === ctx.yo || ctx.admin;
  const vivo = hilo.activo && hilo.estado === "abierto";
  const participo = activos.some((p) => p.asignado_id === ctx.yo);
  const recurrencia = textoRecurrencia(hilo.recurrencia_cantidad, hilo.recurrencia_unidad);
  const pasoSeleccionado = pasos.find((p) => p.id === abierto);

  async function correr(accion: (id: string) => Promise<{ success: boolean; error?: string }>, ok: string) {
    const result = await accion(hilo.id);
    if (!result.success) toast.error(result.error);
    else toast.success(ok);
  }

  const menu = [
    ...(dueno && vivo ? [{ label: "Editar", icon: <Pencil size={14} />, onClick: () => setDialogo("editar") }] : []),
    ...(dueno && hilo.activo ? [{ label: "Transferir", icon: <ArrowLeftRight size={14} />, onClick: () => setDialogo("transferir") }] : []),
    ...(dueno && vivo ? [{ label: "Cerrar hilo", icon: <CheckCircle2 size={14} />, onClick: () => setDialogo("cerrar") }] : []),
    ...(dueno && hilo.activo && hilo.estado === "cerrado"
      ? [{ label: "Reabrir", icon: <RotateCcw size={14} />, onClick: () => correr(reabrirHilo, "Hilo reabierto") }]
      : []),
    ...(dueno && hilo.activo && !activos.some((p) => p.estado === "completada")
      ? [{ label: "Desactivar", icon: <Archive size={14} />, onClick: () => setDialogo("desactivar"), destructive: true }]
      : []),
    ...(ctx.admin && !hilo.activo
      ? [{ label: "Reactivar", icon: <ArchiveRestore size={14} />, onClick: () => correr(reactivarHilo, "Hilo reactivado") }]
      : []),
  ];

  function fila(p: Tarea) {
    const bloqueado = estaBloqueado(p, porId);
    return (
      <button
        key={p.id}
        onClick={() => setAbierto(p.id)}
        className={`flex w-full items-center gap-3 border-b border-border row text-left last:border-b-0 hover:bg-bg-subtle ${
          p.paso_anterior_id && porId.has(p.paso_anterior_id) ? "pl-10" : ""
        }`}
      >
        <div className="min-w-0 flex-1">
          <p className={`t-body-m truncate font-medium ${estaAbierto(p.estado) ? "text-text-primary" : "text-text-tertiary"}`}>
            {p.titulo}
          </p>
          <p className="t-caption flex flex-wrap gap-x-3">
            <span>{p.asignado_id === ctx.yo ? "Vos" : nombre(p.asignado_id ?? p.asignado_equipo_id)}</span>
            {p.vence && <span className={estaVencido(p, hoy) ? "text-error-text" : ""}>Vence {formatFecha(p.vence)}</span>}
            {bloqueado && <span>Espera al anterior</span>}
            {estaEnEspera(p, hoy) && <span>En espera hasta {formatFecha(p.espera_hasta!)}</span>}
          </p>
        </div>
        <span className={`badge ${ESTADO_PASO[p.estado].badge}`}>{ESTADO_PASO[p.estado].label}</span>
        <ChevronRight size={16} strokeWidth={1.75} className="shrink-0 text-text-tertiary" />
      </button>
    );
  }

  return (
    <div className="flex flex-col gap-4">
      <div className="card flex flex-col gap-2">
        <div className="flex flex-wrap items-center gap-2">
          <h2 className="t-h2 min-w-0 flex-1">{hilo.titulo}</h2>
          <span className={`badge ${ESTADO_HILO[hilo.estado].badge}`}>{ESTADO_HILO[hilo.estado].label}</span>
          {!hilo.activo && <span className="badge badge-neutral">Desactivado</span>}
          {menu.length > 0 && <OverflowMenu items={menu} />}
        </div>
        <div className="t-caption flex flex-wrap items-center gap-x-3 gap-y-1">
          <span className="flex items-center gap-1" title="Responsable">
            <UserRound size={12} strokeWidth={1.75} />
            {hilo.responsable_id === ctx.yo ? "Vos" : nombre(hilo.responsable_id)}
          </span>
          {recurrencia && (
            <span className="flex items-center gap-1">
              <Repeat size={12} strokeWidth={1.75} />
              {recurrencia}
            </span>
          )}
          {hilo.recurrencia_de && (
            <Link href={`/tareas/${hilo.recurrencia_de}`} className="text-text-brand hover:underline">
              Ciclo anterior
            </Link>
          )}
        </div>
        {hilo.resultado && <p className="t-body-m whitespace-pre-wrap">{hilo.resultado}</p>}
      </div>

      <div>
        <div className="mb-2 flex items-center">
          <p className="t-label flex-1">Pasos</p>
          {vivo && dueno && plantillas.length > 0 && (
            <button className="btn btn-secondary btn-sm mr-2" onClick={() => setDialogo("plantilla")}>
              <ClipboardList size={14} />
              Usar plantilla
            </button>
          )}
          {vivo && (dueno || participo) && (
            <button className="btn btn-secondary btn-sm" onClick={() => setDialogo("sumar")}>
              <Plus size={14} />
              Sumar paso
            </button>
          )}
        </div>
        {ordenados.length === 0 ? (
          <div className="empty-state">
            <p className="t-body-m">Sin pasos todavía. Sumá el primero con «Sumar paso».</p>
          </div>
        ) : (
          <div className="flex flex-col rounded-lg border border-border bg-bg-surface">{ordenados.map(fila)}</div>
        )}
        {desactivados.length > 0 && (
          <details className="mt-2">
            <summary className="t-label cursor-pointer py-2">Desactivados ({desactivados.length})</summary>
            <div className="flex flex-col rounded-lg border border-border bg-bg-subtle">{desactivados.map(fila)}</div>
          </details>
        )}
      </div>

      <div className="card">
        <p className="t-label mb-2">Notas del hilo</p>
        <NotasSection hiloId={hilo.id} tareaId={null} notas={notas.filter((n) => n.tarea_id === null)} />
        <Historial ediciones={ediciones.filter((e) => e.tarea_id === null)} />
      </div>

      {pasoSeleccionado && (
        <PasoPanel
          hilo={hilo}
          paso={pasoSeleccionado}
          bloqueado={estaBloqueado(pasoSeleccionado, porId)}
          esCola={!conSiguiente.has(pasoSeleccionado.id)}
          notas={notas.filter((n) => n.tarea_id === pasoSeleccionado.id)}
          ediciones={ediciones.filter((e) => e.tarea_id === pasoSeleccionado.id)}
          enlaces={enlaces}
          onClose={() => setAbierto(null)}
        />
      )}
      {dialogo === "sumar" && (
        <PasoFormPanel
          modo={{ tipo: "sumar", hiloId: hilo.id, colas: ordenados.filter((p) => !conSiguiente.has(p.id)), soloYo: !dueno }}
          yo={ctx.yo}
          onClose={() => setDialogo(null)}
        />
      )}
      {dialogo === "plantilla" && (
        <UsarPlantillaPanel plantillas={plantillas} hiloId={hilo.id} onClose={() => setDialogo(null)} />
      )}
      {dialogo === "editar" && <HiloFormPanel hilo={hilo} onClose={() => setDialogo(null)} />}
      {dialogo === "transferir" && <TransferirModal hilo={hilo} onClose={() => setDialogo(null)} />}
      {dialogo === "cerrar" && <CerrarHiloModal hilo={hilo} abiertos={abiertos} onClose={() => setDialogo(null)} />}
      {dialogo === "desactivar" && (
        <ConfirmModal
          title="Desactivar hilo"
          mensaje={`¿Desactivar "${hilo.titulo}"? Deja de verse con todos sus pasos.`}
          onConfirm={() => correr(desactivarHilo, "Hilo desactivado")}
          onClose={() => setDialogo(null)}
        />
      )}
    </div>
  );
}
