"use client";

import { useState } from "react";
import Link from "next/link";
import { CircleCheck } from "lucide-react";
import { toast } from "sonner";
import { formatFecha, hoyISO } from "@/lib/utils";
import { aceptarPaso } from "../actions";
import { compararMision, estaBloqueado, estaEnEspera, estaVencido } from "../derivados";
import { PRIORIDAD, textoPlazoDias } from "../etiquetas";
import type { HiloResumen, PasoCadena, PasoEquipo } from "../queries";
import { TareasProvider, useNombre, useTareas, type TareasCtx } from "./contexto";
import { HilosView } from "./HilosView";
import { CompletarModal, EsperaModal, ReasignarModal, RechazarModal } from "./PasoModales";

const TIPOS = [
  { valor: "pedidos", label: "Pedidos" },
  { valor: "equipo", label: "Al equipo" },
  { valor: "hilos", label: "Hilos" },
] as const;

type Tipo = (typeof TIPOS)[number]["valor"];
type Dialogo = { tipo: "rechazar" | "completar" | "espera" | "repartir"; paso: PasoEquipo };

// La bandeja del delegador: lo que su equipo tiene por decidir, lo que espera
// reparto y los hilos donde participa. El resto de los gestos, en el hilo.
type Datos = { pasos: PasoEquipo[]; cadena: PasoCadena[]; hilos: HiloResumen[] };

export function EquipoView({ ctx, ...datos }: Datos & { ctx: TareasCtx }) {
  return (
    <TareasProvider value={ctx}>
      <Contenido {...datos} />
    </TareasProvider>
  );
}

function Contenido({ pasos, cadena, hilos }: Datos) {
  const { yo, miEquipo, asignables, nombres } = useTareas();
  const nombre = useNombre();
  const [tipo, setTipo] = useState<Tipo>("pedidos");
  const [miembro, setMiembro] = useState("");
  const [dialogo, setDialogo] = useState<Dialogo | null>(null);
  const hoy = hoyISO();
  const porId = new Map(cadena.map((p) => [p.id, p]));

  const miembros = asignables.filter((a) => a.usuario_id && !a.pedido);
  const esDe = (p: PasoEquipo) => !miembro || p.asignado_id === miembro;
  const pedidos = pasos.filter((p) => p.estado === "solicitada" && esDe(p)).sort(compararMision);
  const alEquipo = pasos.filter((p) => p.estado === "pendiente" && p.asignado_equipo_id === miEquipo).sort(compararMision);
  const hilosFiltrados = miembro
    ? hilos.filter((h) => h.responsable_id === miembro || h.tareas.some((t) => t.activo && t.asignado_id === miembro))
    : hilos;
  const cuenta: Record<Tipo, number> = { pedidos: pedidos.length, equipo: alEquipo.length, hilos: hilosFiltrados.length };

  function motivoEspera(p: PasoEquipo) {
    if (p.estado !== "pendiente") return null;
    if (estaBloqueado(p, porId)) {
      const previo = p.paso_anterior_id ? porId.get(p.paso_anterior_id) : undefined;
      return previo ? `Espera a «${previo.titulo}»` : "Espera al paso anterior";
    }
    if (estaEnEspera(p, hoy)) return `En espera hasta ${formatFecha(p.espera_hasta!)}${p.espera_motivo ? ` · ${p.espera_motivo}` : ""}`;
    return null;
  }

  function fila(p: PasoEquipo) {
    const vence = p.vence ? formatFecha(p.vence) : p.vence_dias ? textoPlazoDias(p.vence_dias) : null;
    const espera = motivoEspera(p);
    return (
      <div key={p.id} className="flex flex-wrap items-center gap-x-3 gap-y-2 border-b border-border row last:border-b-0">
        <div className="min-w-0 flex-1 basis-64">
          <Link href={`/tareas/paso/${p.id}`} className="t-body-m block truncate font-medium text-text-primary hover:text-text-brand">
            {p.titulo}
          </Link>
          <p className="t-caption flex flex-wrap items-center gap-x-3 gap-y-1">
            <span className="truncate">{p.tareas_hilos.titulo}</span>
            {p.estado === "solicitada" && (
              <span>
                Pide {p.tareas_hilos.responsable_id === yo ? "vos" : nombre(p.tareas_hilos.responsable_id)} a{" "}
                {p.asignado_equipo_id ? "el equipo" : nombre(p.asignado_id)}
              </span>
            )}
            {estaVencido(p, hoy) && <span className="text-error-text">Vencido</span>}
            {p.prioridad !== "media" && <span className={PRIORIDAD[p.prioridad].clase}>Prioridad {PRIORIDAD[p.prioridad].label.toLowerCase()}</span>}
            {vence && <span>Vence {vence}</span>}
            {espera && <span>{espera}</span>}
          </p>
        </div>
        <div className="flex flex-wrap gap-2">
          {p.estado === "solicitada" ? (
            <>
              <button
                className="btn btn-sm btn-primary"
                onClick={async () => {
                  const result = await aceptarPaso(p.id);
                  if (!result.success) toast.error(result.error);
                  else toast.success("Pedido aceptado");
                }}
              >
                Aceptar
              </button>
              <button className="btn btn-sm btn-secondary text-error-text" onClick={() => setDialogo({ tipo: "rechazar", paso: p })}>
                Rechazar
              </button>
            </>
          ) : (
            <>
              {!estaBloqueado(p, porId) && (
                <button className="btn btn-sm btn-secondary" onClick={() => setDialogo({ tipo: "completar", paso: p })}>
                  Completar
                </button>
              )}
              <button className="btn btn-sm btn-secondary" onClick={() => setDialogo({ tipo: "espera", paso: p })}>
                {p.espera_hasta ? "Cambiar espera" : "Poner en espera"}
              </button>
            </>
          )}
          <button className="btn btn-sm btn-secondary" onClick={() => setDialogo({ tipo: "repartir", paso: p })}>
            Repartir
          </button>
        </div>
      </div>
    );
  }

  function lista(filas: PasoEquipo[], vacio: string) {
    if (filas.length === 0)
      return (
        <div className="empty-state">
          <CircleCheck size={30} strokeWidth={1.5} className="mx-auto mb-3 text-success" />
          <p className="t-h3">{vacio}</p>
        </div>
      );
    return <div className="flex flex-col rounded-lg border border-border bg-bg-surface">{filas.map(fila)}</div>;
  }

  return (
    <div>
      <div className="mb-4 flex flex-wrap items-center gap-3">
        <div className="flex rounded-lg border border-border p-0.5" role="group" aria-label="Qué ver">
          {TIPOS.map((t) => (
            <button
              key={t.valor}
              onClick={() => setTipo(t.valor)}
              aria-pressed={t.valor === tipo}
              className={`tap-target t-caption flex items-center rounded-md px-3 py-1 ${
                t.valor === tipo ? "bg-brand-50 font-semibold text-brand-700" : "text-text-tertiary"
              }`}
            >
              {t.label} ({cuenta[t.valor]})
            </button>
          ))}
        </div>
        {tipo !== "equipo" && (
          <select className="input w-auto" value={miembro} onChange={(e) => setMiembro(e.target.value)} aria-label="Filtrar por miembro">
            <option value="">Todo el equipo</option>
            {miembros.map((m) => (
              <option key={m.usuario_id} value={m.usuario_id}>
                {m.nombre}
              </option>
            ))}
          </select>
        )}
      </div>

      {tipo === "pedidos" && lista(pedidos, "Sin pedidos por decidir.")}
      {tipo === "equipo" && lista(alEquipo, "Nada asignado al equipo sin repartir.")}
      {tipo === "hilos" && <HilosView hilos={hilosFiltrados} yo={yo} nombres={nombres} vacio="Acá aparecen los hilos donde participa alguien del equipo." />}

      {dialogo?.tipo === "rechazar" && <RechazarModal paso={dialogo.paso} devolver={false} onClose={() => setDialogo(null)} />}
      {dialogo?.tipo === "completar" && <CompletarModal paso={dialogo.paso} onClose={() => setDialogo(null)} />}
      {dialogo?.tipo === "espera" && <EsperaModal paso={dialogo.paso} onClose={() => setDialogo(null)} />}
      {dialogo?.tipo === "repartir" && <ReasignarModal paso={dialogo.paso} soloMiEquipo onClose={() => setDialogo(null)} />}
    </div>
  );
}
