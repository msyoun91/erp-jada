"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { ChevronDown, ChevronLeft, ChevronRight, ChevronUp, CircleCheck, Clock, Lock } from "lucide-react";
import { toast } from "sonner";
import { formatFecha, hoyISO } from "@/lib/utils";
import { aceptarPaso } from "../actions";
import { compararMision, estaBloqueado, estaEnEspera, estaVencido } from "../derivados";
import { PRIORIDAD, textoPlazoDias } from "../etiquetas";
import type { PasoCadena, PasoMision } from "../queries";
import { CompletarModal, EsperaModal, RechazarModal } from "./PasoModales";
import { TextoConReferencias } from "./TextoConReferencias";

type Dialogo = "rechazar" | "completar" | "espera";

// De a un paso: lo que toca ahora. Un pedido se decide aunque espere al
// anterior; un pendiente bloqueado o en espera no toca todavía.
export function MisionView({ pasos, cadena }: { pasos: PasoMision[]; cadena: PasoCadena[] }) {
  const [indice, setIndice] = useState(0);
  const [dialogo, setDialogo] = useState<Dialogo | null>(null);
  const hoy = hoyISO();
  const porId = new Map(cadena.map((p) => [p.id, p]));

  const bloqueados = pasos.filter((p) => p.estado === "pendiente" && estaBloqueado(p, porId));
  const enEspera = pasos.filter((p) => !bloqueados.includes(p) && estaEnEspera(p, hoy));
  const cola = pasos.filter((p) => !bloqueados.includes(p) && !enEspera.includes(p)).sort(compararMision);
  const total = cola.length;

  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      if (e.key !== "ArrowLeft" && e.key !== "ArrowRight") return;
      if (document.querySelector("dialog[open]")) return;
      const destino = e.target as HTMLElement | null;
      if (destino && ["INPUT", "SELECT", "TEXTAREA"].includes(destino.tagName)) return;
      setIndice((i) => Math.min(Math.max(i + (e.key === "ArrowLeft" ? -1 : 1), 0), Math.max(total - 1, 0)));
    }
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [total]);

  // Se recorta en vez de resetearse: al completar, la misma posición muestra el siguiente.
  const posicion = Math.min(indice, Math.max(total - 1, 0));
  const actual = cola[posicion];
  const esperando = (
    <Esperando
      pasos={[...bloqueados, ...enEspera]}
      motivo={(p) => {
        if (!bloqueados.includes(p)) return `En espera hasta ${formatFecha(p.espera_hasta!)}${p.espera_motivo ? ` · ${p.espera_motivo}` : ""}`;
        const previo = p.paso_anterior_id ? porId.get(p.paso_anterior_id) : undefined;
        return previo ? `Espera a «${previo.titulo}»` : "Espera al paso anterior";
      }}
    />
  );

  if (!actual) {
    const hayEsperando = bloqueados.length + enEspera.length > 0;
    return (
      <div className="mx-auto flex w-full max-w-2xl flex-col gap-3">
        <div className="empty-state">
          {hayEsperando ? (
            <Lock size={30} strokeWidth={1.5} className="mx-auto mb-3 text-warning" />
          ) : (
            <CircleCheck size={30} strokeWidth={1.5} className="mx-auto mb-3 text-success" />
          )}
          <p className="t-h3">No hay nada para hacer ahora.</p>
          <p className="t-body-m mt-1">
            {hayEsperando
              ? "Todo lo tuyo espera a un paso anterior o está en espera."
              : "Cuando te asignen o te pidan un paso, va a aparecer acá."}
          </p>
        </div>
        {esperando}
      </div>
    );
  }

  const siguiente = cola[posicion + 1];
  const vence = actual.vence ? formatFecha(actual.vence) : actual.vence_dias ? textoPlazoDias(actual.vence_dias) : null;

  return (
    <div className="mx-auto flex w-full max-w-2xl flex-col gap-4">
      <div className="flex flex-col gap-2">
        <div className="flex items-center justify-between gap-3">
          <p className="t-label">
            Paso {posicion + 1} de {total}
          </p>
          <div className="flex items-center gap-2">
            <button
              className="btn btn-secondary btn-sm"
              onClick={() => setIndice(posicion - 1)}
              disabled={posicion === 0}
              aria-label="Paso anterior"
            >
              <ChevronLeft size={16} />
            </button>
            <button
              className="btn btn-secondary btn-sm"
              onClick={() => setIndice(posicion + 1)}
              disabled={posicion >= total - 1}
              aria-label="Paso siguiente"
            >
              <ChevronRight size={16} />
            </button>
          </div>
        </div>
        <div className="h-1 w-full overflow-hidden rounded-full bg-bg-subtle">
          <div
            className="h-full rounded-full bg-brand-500 transition-[width]"
            style={{ width: `${((posicion + 1) / total) * 100}%` }}
          />
        </div>
      </div>

      <div className="flex flex-col gap-4 rounded-lg border border-border bg-bg-surface px-5 py-4">
        <div className="flex flex-col gap-1">
          <Link href={`/tareas/${actual.hilo_id}`} className="t-caption truncate hover:text-text-brand">
            {actual.tareas_hilos.titulo}
          </Link>
          <p className="t-h2">{actual.titulo}</p>
          <p className="t-caption flex flex-wrap items-center gap-x-3 gap-y-1">
            {actual.estado === "solicitada" && <span className="badge badge-info">Te lo piden</span>}
            {estaVencido(actual, hoy) && <span className="badge badge-error">Vencido</span>}
            <span className={PRIORIDAD[actual.prioridad].clase}>Prioridad {PRIORIDAD[actual.prioridad].label.toLowerCase()}</span>
            {vence && <span>Vence {vence}</span>}
          </p>
        </div>

        {actual.descripcion && <TextoConReferencias texto={actual.descripcion} />}

        <div className="flex flex-wrap gap-2">
          {actual.estado === "solicitada" ? (
            <>
              <button
                className="btn btn-sm btn-primary"
                onClick={async () => {
                  const result = await aceptarPaso(actual.id);
                  if (!result.success) toast.error(result.error);
                  else toast.success("Pedido aceptado");
                }}
              >
                Aceptar
              </button>
              <button className="btn btn-sm btn-secondary text-error-text" onClick={() => setDialogo("rechazar")}>
                Rechazar
              </button>
            </>
          ) : (
            <>
              <button className="btn btn-sm btn-primary" onClick={() => setDialogo("completar")}>
                Completar
              </button>
              <button className="btn btn-sm btn-secondary" onClick={() => setDialogo("espera")}>
                Poner en espera
              </button>
            </>
          )}
          <Link href={`/tareas/paso/${actual.id}`} className="btn btn-sm btn-ghost">
            Abrir en el hilo
          </Link>
        </div>
      </div>

      {siguiente && (
        <p className="t-caption truncate">
          Sigue: <span className="text-text-secondary">{siguiente.titulo}</span>
        </p>
      )}

      {esperando}

      {dialogo === "rechazar" && <RechazarModal paso={actual} devolver={false} onClose={() => setDialogo(null)} />}
      {dialogo === "completar" && <CompletarModal paso={actual} onClose={() => setDialogo(null)} />}
      {dialogo === "espera" && <EsperaModal paso={actual} onClose={() => setDialogo(null)} />}
    </div>
  );
}

// Una cola vacía con trabajo detrás se lee como una vista rota: se ve qué frena qué.
function Esperando({ pasos, motivo }: { pasos: PasoMision[]; motivo: (p: PasoMision) => string }) {
  const [abierto, setAbierto] = useState(false);
  if (pasos.length === 0) return null;

  return (
    <div className="flex flex-col gap-2">
      <button className="btn btn-ghost btn-sm self-start" onClick={() => setAbierto(!abierto)}>
        <Clock size={14} strokeWidth={1.75} />
        {pasos.length} {pasos.length === 1 ? "paso esperando" : "pasos esperando"}
        {abierto ? <ChevronUp size={14} /> : <ChevronDown size={14} />}
      </button>
      {abierto && (
        <div className="flex flex-col rounded-lg border border-border bg-bg-surface">
          {pasos.map((p) => (
            <Link
              key={p.id}
              href={`/tareas/paso/${p.id}`}
              className="flex items-center gap-3 border-b border-border row last:border-b-0 hover:bg-bg-subtle"
            >
              <div className="min-w-0 flex-1">
                <p className="t-body-m truncate font-medium text-text-primary">{p.titulo}</p>
                <p className="t-caption truncate">
                  {p.tareas_hilos.titulo} · {motivo(p)}
                </p>
              </div>
              <ChevronRight size={16} strokeWidth={1.75} className="shrink-0 text-text-tertiary" />
            </Link>
          ))}
        </div>
      )}
    </div>
  );
}
