"use client";

import { useState } from "react";
import { toast } from "sonner";
import { RightPanel } from "@/components/ui/RightPanel";
import { ConfirmModal } from "@/components/ui/Modal";
import { formatFecha, hoyISO } from "@/lib/utils";
import { aceptarPaso, cancelarPaso, desactivarPaso, reabrirPaso, reactivarPaso, volverAPedir } from "../actions";
import { estaAbierto, estaEnEspera, estaVencido } from "../derivados";
import { ESTADO_PASO, PRIORIDAD, textoPlazoDias } from "../etiquetas";
import type { Edicion, Hilo, Nota, Tarea } from "../types";
import { useNombre, useTareas } from "./contexto";
import { Historial } from "./Historial";
import { NotasSection } from "./NotasSection";
import { PasoFormPanel } from "./PasoFormPanel";
import { CompletarAjenoModal, CompletarModal, EsperaModal, ReasignarModal, RechazarModal } from "./PasoModales";
import { TextoConReferencias } from "./TextoConReferencias";

type Dialogo =
  | "editar"
  | "antes"
  | "rechazar"
  | "devolver"
  | "completar"
  | "completarAjeno"
  | "espera"
  | "reasignar"
  | "repartir"
  | "cancelar"
  | "desactivar";

export function PasoPanel({
  hilo,
  paso,
  bloqueado,
  esCola,
  notas,
  ediciones,
  enlaces,
  onClose,
}: {
  hilo: Hilo;
  paso: Tarea;
  bloqueado: boolean;
  // Sin siguiente activo: se desactiva desde la cola (TA006).
  esCola: boolean;
  notas: Nota[];
  ediciones: Edicion[];
  enlaces: Record<string, string>;
  onClose: () => void;
}) {
  const { yo, miEquipo, admin, delegador } = useTareas();
  const nombre = useNombre();
  const [dialogo, setDialogo] = useState<Dialogo | null>(null);
  const hoy = hoyISO();

  // Lo que se muestra; quien decide es `tareas_al_editar` (sql/113).
  const resp = hilo.responsable_id === yo;
  const asig =
    paso.asignado_id === yo || (delegador && paso.asignado_equipo_id !== null && paso.asignado_equipo_id === miEquipo);
  const deleg = delegador && miEquipo !== null && paso.equipo_id === miEquipo;
  const dueno = resp || admin;
  const vivo = hilo.activo && hilo.estado === "abierto" && paso.activo;
  const pedido = paso.equipo_id !== hilo.equipo_id || (hilo.equipo_id === null && paso.asignado_id !== hilo.responsable_id);
  const e = paso.estado;

  async function correr(accion: (id: string) => Promise<{ success: boolean; error?: string }>, ok: string) {
    const result = await accion(paso.id);
    if (!result.success) toast.error(result.error);
    else toast.success(ok);
  }

  const acciones: { label: string; onClick: () => void; primaria?: boolean; peligro?: boolean }[] = [];
  if (vivo) {
    if (e === "solicitada" && (asig || deleg || admin)) {
      acciones.push({ label: "Aceptar", primaria: true, onClick: () => correr(aceptarPaso, "Pedido aceptado") });
      acciones.push({ label: "Rechazar", peligro: true, onClick: () => setDialogo("rechazar") });
    }
    if (e === "pendiente" && !bloqueado && asig) acciones.push({ label: "Completar", primaria: true, onClick: () => setDialogo("completar") });
    if (e === "pendiente" && !bloqueado && admin && !asig) acciones.push({ label: "Completar (admin)", onClick: () => setDialogo("completarAjeno") });
    if (e === "pendiente" && (asig || admin)) acciones.push({ label: paso.espera_hasta ? "Cambiar espera" : "Poner en espera", onClick: () => setDialogo("espera") });
    if (e === "pendiente" && pedido && (asig || deleg || admin)) acciones.push({ label: "Devolver", peligro: true, onClick: () => setDialogo("devolver") });
    if (e === "rechazada" && dueno) acciones.push({ label: "Volver a pedir", primaria: true, onClick: () => correr(volverAPedir, "Pedido enviado de nuevo") });
    if (estaAbierto(e) && dueno) acciones.push({ label: "Reasignar", onClick: () => setDialogo("reasignar") });
    else if ((e === "solicitada" || e === "pendiente") && deleg) acciones.push({ label: "Repartir en el equipo", onClick: () => setDialogo("repartir") });
    if (estaAbierto(e) && dueno) {
      acciones.push({ label: "Editar", onClick: () => setDialogo("editar") });
      acciones.push({ label: "Insertar paso antes", onClick: () => setDialogo("antes") });
      acciones.push({ label: "Cancelar paso", peligro: true, onClick: () => setDialogo("cancelar") });
      if (esCola) acciones.push({ label: "Desactivar", peligro: true, onClick: () => setDialogo("desactivar") });
    }
    if ((e === "completada" && (dueno || asig)) || (e === "cancelada" && dueno))
      acciones.push({ label: "Reabrir", onClick: () => correr(reabrirPaso, "Paso reabierto") });
  }
  if (!paso.activo && admin) acciones.push({ label: "Reactivar", onClick: () => correr(reactivarPaso, "Paso reactivado") });

  const datos: [string, React.ReactNode][] = [
    ["Asignado", nombre(paso.asignado_id ?? paso.asignado_equipo_id)],
    ["Prioridad", <span key="p" className={PRIORIDAD[paso.prioridad].clase}>{PRIORIDAD[paso.prioridad].label}</span>],
    ["Vence", paso.vence ? formatFecha(paso.vence) : paso.vence_dias ? textoPlazoDias(paso.vence_dias) : "—"],
  ];
  if (estaEnEspera(paso, hoy))
    datos.push(["En espera", `Hasta ${formatFecha(paso.espera_hasta!)}${paso.espera_motivo ? ` · ${paso.espera_motivo}` : ""}`]);
  if (paso.motivo_rechazo && e === "rechazada") datos.push(["Motivo del rechazo", paso.motivo_rechazo]);
  if (paso.resultado) datos.push(["Resultado", paso.resultado]);

  return (
    <RightPanel title={paso.titulo} subtitle={hilo.titulo} onClose={onClose}>
      <div className="flex min-h-0 flex-1 flex-col gap-4 overflow-y-auto px-5 py-4">
        <div className="flex flex-wrap items-center gap-2">
          <span className={`badge ${ESTADO_PASO[e].badge}`}>{ESTADO_PASO[e].label}</span>
          {bloqueado && <span className="badge badge-neutral">Espera al anterior</span>}
          {estaVencido(paso, hoy) && <span className="badge badge-error">Vencido</span>}
          {!paso.activo && <span className="badge badge-neutral">Desactivado</span>}
        </div>

        {paso.descripcion && <TextoConReferencias texto={paso.descripcion} enlaces={enlaces} />}

        <dl className="grid grid-cols-[auto_1fr] gap-x-4 gap-y-2">
          {datos.map(([k, v]) => (
            <div key={k} className="contents">
              <dt className="t-caption">{k}</dt>
              <dd className="t-body-m whitespace-pre-wrap">{v}</dd>
            </div>
          ))}
        </dl>

        {acciones.length > 0 && (
          <div className="flex flex-wrap gap-2">
            {acciones.map((a) => (
              <button
                key={a.label}
                className={`btn btn-sm ${a.primaria ? "btn-primary" : "btn-secondary"} ${a.peligro ? "text-error-text" : ""}`}
                onClick={a.onClick}
              >
                {a.label}
              </button>
            ))}
          </div>
        )}

        <div className="border-t border-border pt-4">
          <p className="t-label mb-2">Notas del paso</p>
          <NotasSection hiloId={hilo.id} tareaId={paso.id} notas={notas} />
        </div>

        <Historial ediciones={ediciones} />
      </div>

      {dialogo === "editar" && <PasoFormPanel modo={{ tipo: "editar", paso }} yo={yo} onClose={() => setDialogo(null)} />}
      {dialogo === "antes" && <PasoFormPanel modo={{ tipo: "antes", siguiente: paso }} yo={yo} onClose={() => setDialogo(null)} />}
      {dialogo === "rechazar" && <RechazarModal paso={paso} devolver={false} onClose={() => setDialogo(null)} />}
      {dialogo === "devolver" && <RechazarModal paso={paso} devolver onClose={() => setDialogo(null)} />}
      {dialogo === "completar" && <CompletarModal paso={paso} onClose={() => setDialogo(null)} />}
      {dialogo === "completarAjeno" && <CompletarAjenoModal paso={paso} onClose={() => setDialogo(null)} />}
      {dialogo === "espera" && <EsperaModal paso={paso} onClose={() => setDialogo(null)} />}
      {dialogo === "reasignar" && <ReasignarModal paso={paso} soloMiEquipo={false} onClose={() => setDialogo(null)} />}
      {dialogo === "repartir" && <ReasignarModal paso={paso} soloMiEquipo onClose={() => setDialogo(null)} />}
      {dialogo === "cancelar" && (
        <ConfirmModal
          title="Cancelar paso"
          mensaje={`¿Cancelar "${paso.titulo}"? Se puede reabrir después.`}
          confirmLabel="Cancelar paso"
          cancelLabel="Volver"
          onConfirm={() => correr(cancelarPaso, "Paso cancelado")}
          onClose={() => setDialogo(null)}
        />
      )}
      {dialogo === "desactivar" && (
        <ConfirmModal
          title="Desactivar paso"
          mensaje={`¿Desactivar "${paso.titulo}"? Deja de verse en el hilo.`}
          onConfirm={async () => {
            await correr(desactivarPaso, "Paso desactivado");
            onClose();
          }}
          onClose={() => setDialogo(null)}
        />
      )}
    </RightPanel>
  );
}
