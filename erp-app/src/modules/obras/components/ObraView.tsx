"use client";

import { useState } from "react";
import { usePathname, useRouter } from "next/navigation";
import { Archive, ArchiveRestore, ArrowLeftRight, CalendarClock, Flag, MapPin, Pencil, Plus, UserRound, X } from "lucide-react";
import { toast } from "sonner";
import { ConfirmModal } from "@/components/ui/Modal";
import { OverflowMenu } from "@/components/ui/OverflowMenu";
import { ENTES, labelRol, type CodigoEnte } from "@/lib/entes";
import type { UsuarioBasico } from "@/lib/usuarios";
import { formatFechaHora } from "@/lib/utils";
import { desactivarObra, quitarParticipante, reactivarObra } from "../actions";
import { MOTIVO, ORIGEN, TIPO } from "../etiquetas";
import type { Evento, ObraCompleta } from "../queries";
import { LABEL_ESTADO, type EstadoObra } from "../types";
import { EditarObraPanel } from "./ObraFormPanel";
import { EstadoModal, SumarParticipanteModal, TransferirModal } from "./ObraModales";

type Dialogo = "editar" | "estado" | "transferir" | "desactivar" | "sumar";

function mesAnio(fecha: string) {
  return new Date(`${fecha}T12:00:00Z`).toLocaleDateString("es-AR", { month: "long", year: "numeric", timeZone: "UTC" });
}

function textoEvento(e: Evento, nombre: (id: string | null) => string) {
  const d = (e.detalle ?? {}) as Record<string, string | undefined>;
  const contacto = ENTES[d.ente as CodigoEnte]?.un ?? "un contacto";
  switch (e.evento) {
    case "alta":
      return "Cargó la obra";
    case "estado":
      return `Pasó a ${LABEL_ESTADO[d.estado as EstadoObra]?.label ?? d.estado}`;
    case "transferencia":
      return `La pasó de ${nombre(d.de ?? null)} a ${nombre(d.a ?? null)}`;
    case "baja":
      return "Desactivó la obra";
    case "reactivacion":
      return "Reactivó la obra";
    case "relacion_alta":
      return `Vinculó ${contacto} como ${labelRol("obra", d.rol ?? "")}`;
    case "relacion_baja":
      return `Cerró ${contacto} como ${labelRol("obra", d.rol ?? "")}`;
    default:
      return e.evento;
  }
}

type Props = ObraCompleta & {
  yo: string;
  admin: boolean;
  nombres: Record<string, string>;
  candidatos: UsuarioBasico[];
  // `?estado={estado}`: link de acción de Tareas.
  estadoInicial: EstadoObra | null;
  // Los contactos los dibuja Contactos; `app/` los compone (GUIDE_ENTES §2.7).
  contactos: React.ReactNode;
};

export function ObraView({ obra, participantes, historial, trabaja, aCargo, yo, admin, nombres, candidatos, estadoInicial, contactos }: Props) {
  const router = useRouter();
  const pathname = usePathname();
  const [dialogo, setDialogo] = useState<Dialogo | null>(trabaja && estadoInicial ? "estado" : null);
  const [quitando, setQuitando] = useState<{ id: string; nombre: string } | null>(null);
  const nombre = (id: string | null) => (id ? (id === yo ? "Vos" : (nombres[id] ?? "—")) : "—");

  function cerrar() {
    setDialogo(null);
    if (estadoInicial) router.replace(pathname, { scroll: false });
  }

  async function correr(accion: (id: string) => Promise<{ success: boolean; error?: string }>, ok: string) {
    const result = await accion(obra.id);
    if (!result.success) toast.error(result.error);
    else toast.success(ok);
  }

  const menu = [
    ...(trabaja ? [{ label: "Editar", icon: <Pencil size={14} />, onClick: () => setDialogo("editar") }] : []),
    ...(aCargo ? [{ label: "Transferir", icon: <ArrowLeftRight size={14} />, onClick: () => setDialogo("transferir") }] : []),
    ...(aCargo && obra.estado !== "contratada"
      ? [{ label: "Desactivar", icon: <Archive size={14} />, onClick: () => setDialogo("desactivar"), destructive: true }]
      : []),
    ...(admin && !obra.activo
      ? [{ label: "Reactivar", icon: <ArchiveRestore size={14} />, onClick: () => correr(reactivarObra, "Obra reactivada") }]
      : []),
  ];

  const yaEstan = new Set([obra.responsable_id, ...participantes.map((p) => p.usuario_id)]);
  const motivo = obra.motivo_perdida ? MOTIVO[obra.motivo_perdida].label : null;

  return (
    <div className="flex flex-col gap-4">
      <div className="card flex flex-col gap-3">
        <div className="flex flex-wrap items-center gap-2">
          <h2 className="t-h2 min-w-0 flex-1">{obra.nombre}</h2>
          {trabaja ? (
            <button
              className={`badge ${LABEL_ESTADO[obra.estado].badge} cursor-pointer`}
              onClick={() => setDialogo("estado")}
              title="Cambiar estado"
            >
              {LABEL_ESTADO[obra.estado].label}
            </button>
          ) : (
            <span className={`badge ${LABEL_ESTADO[obra.estado].badge}`}>{LABEL_ESTADO[obra.estado].label}</span>
          )}
          {!obra.activo && <span className="badge badge-neutral">Desactivada</span>}
          {menu.length > 0 && <OverflowMenu items={menu} />}
        </div>
        <div className="t-caption flex flex-wrap items-center gap-x-3 gap-y-1">
          <span className="flex items-center gap-1">
            <MapPin size={12} strokeWidth={1.75} />
            {obra.localidad ? `${obra.direccion}, ${obra.localidad}` : obra.direccion}
          </span>
          <span className="flex items-center gap-1" title="Responsable">
            <UserRound size={12} strokeWidth={1.75} />
            {nombre(obra.responsable_id)}
          </span>
          <span>{TIPO[obra.tipo]}</span>
          <span className="flex items-center gap-1" title="Origen">
            <Flag size={12} strokeWidth={1.75} />
            {ORIGEN[obra.origen]}
          </span>
          {obra.compra_estimada && (
            <span className="flex items-center gap-1" title="Compra estimada">
              <CalendarClock size={12} strokeWidth={1.75} />
              Compra en {mesAnio(obra.compra_estimada)}
            </span>
          )}
        </div>
        {(motivo || obra.estado_nota) && (
          <p className="t-body-m rounded-md bg-bg-subtle px-3 py-2">
            {motivo && <span className="font-semibold">{motivo}. </span>}
            {obra.estado_nota}
          </p>
        )}
        {obra.notas && <p className="t-body-m whitespace-pre-wrap">{obra.notas}</p>}
      </div>

      {contactos}

      <div>
        <div className="mb-2 flex items-center">
          <p className="t-label flex-1">Participantes</p>
          {aCargo && (
            <button className="btn btn-secondary btn-sm" onClick={() => setDialogo("sumar")}>
              <Plus size={14} />
              Sumar participante
            </button>
          )}
        </div>
        {participantes.length === 0 ? (
          <div className="empty-state">
            <p className="t-body-m">Solo {obra.responsable_id === yo ? "vos" : nombre(obra.responsable_id)}.</p>
          </div>
        ) : (
          <ul className="flex flex-col rounded-lg border border-border bg-bg-surface">
            {participantes.map((p) => (
              <li key={p.id} className="row flex items-center gap-3 border-b border-border last:border-b-0">
                <UserRound size={14} strokeWidth={1.75} className="shrink-0 text-text-tertiary" />
                <p className="t-body-m min-w-0 flex-1 truncate">{nombre(p.usuario_id)}</p>
                {aCargo && (
                  <button
                    className="icon-btn text-text-tertiary"
                    onClick={() => setQuitando({ id: p.id, nombre: nombre(p.usuario_id) })}
                    aria-label={`Quitar a ${nombre(p.usuario_id)}`}
                  >
                    <X size={16} strokeWidth={1.75} />
                  </button>
                )}
              </li>
            ))}
          </ul>
        )}
      </div>

      {historial.length > 0 && (
        <div className="card">
          <details>
            <summary className="t-label cursor-pointer py-2">Historial ({historial.length})</summary>
            <ul className="flex flex-col gap-1">
              {[...historial].reverse().map((e) => (
                <li key={e.id} className="t-caption">
                  <span className="text-text-secondary">{textoEvento(e, nombre)}</span> · {nombre(e.actor_id)} ·{" "}
                  {formatFechaHora(e.created_at)}
                </li>
              ))}
            </ul>
          </details>
        </div>
      )}

      {dialogo === "editar" && <EditarObraPanel obra={obra} onClose={cerrar} />}
      {dialogo === "estado" && <EstadoModal obra={obra} inicial={estadoInicial} onClose={cerrar} />}
      {dialogo === "transferir" && <TransferirModal obra={obra} candidatos={candidatos} onClose={cerrar} />}
      {dialogo === "sumar" && (
        <SumarParticipanteModal obraId={obra.id} candidatos={candidatos.filter((c) => !yaEstan.has(c.id))} onClose={cerrar} />
      )}
      {dialogo === "desactivar" && (
        <ConfirmModal
          title="Desactivar obra"
          mensaje={`¿Desactivar "${obra.nombre}"? Deja de verse para todos, con sus contactos.`}
          onConfirm={async () => {
            const result = await desactivarObra(obra.id);
            if (!result.success) {
              toast.error(result.error);
              return;
            }
            toast.success("Obra desactivada");
            if (!admin) router.push("/obras");
          }}
          onClose={cerrar}
        />
      )}
      {quitando && (
        <ConfirmModal
          title="Quitar participante"
          mensaje={`¿Quitar a ${quitando.nombre}? Deja de ver la obra, salvo que la vea por su equipo.`}
          confirmLabel="Quitar"
          onConfirm={async () => {
            const result = await quitarParticipante(quitando.id);
            if (!result.success) toast.error(result.error);
            else toast.success("Participante quitado");
          }}
          onClose={() => setQuitando(null)}
        />
      )}
    </div>
  );
}
