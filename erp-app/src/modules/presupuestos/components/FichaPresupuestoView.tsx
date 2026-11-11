import Link from "next/link";
import { Building2, ChevronRight, Printer } from "lucide-react";
import { ENTES, MOTIVO_PERDIDA } from "@/lib/entes";
import { diasEntreISO, formatFecha, hoyISO } from "@/lib/utils";
import type { FichaPresupuesto } from "../queries";
import { estadoVersion, estaVencida } from "../types";
import { AccionesPresupuesto, AccionesVariante, EditarNombre, type Aprobable } from "./AccionesFicha";

const QUITADA = { label: "Quitada", badge: "badge-neutral" };

export function FichaPresupuestoView({
  presupuesto: p,
}: {
  presupuesto: FichaPresupuesto;
}) {
  const variantes = Map.groupBy(p.versiones, (v) => v.variante);
  const grupos = [...variantes]
    .sort(([a], [b]) => a - b)
    .map(([variante, versiones]) => ({
      variante,
      versiones,
      nombre:
        versiones.find((v) => v.variante_nombre)?.variante_nombre ??
        (variantes.size > 1 ? `Variante ${variante}` : "Presupuesto"),
    }));
  const estado = ENTES.presupuesto.estados[p.estado];
  const publicadas = p.versiones.filter((v) => v.estado === "publicado").length;
  const hoy = hoyISO();
  const aprobables: Aprobable[] = grupos.flatMap((g) =>
    g.versiones
      .filter((v) => v.estado === "publicado")
      .map((v) => {
        const dias = v.vence && estaVencida(v, hoy) ? diasEntreISO(v.vence, hoy) : null;
        const del = p.precios_del[v.id];
        return {
          id: v.id,
          numero: v.numero,
          nombre: g.nombre,
          vencida:
            dias === null
              ? null
              : `Vencida hace ${dias} ${dias === 1 ? "día" : "días"}${del ? `: los precios son del ${formatFecha(del)}` : ""}.`,
        };
      }),
  );
  const abiertas = p.versiones
    .filter((v) => v.estado === "borrador" || v.estado === "en_revision")
    .map((v) => v.numero)
    .sort((a, b) => a - b);
  // Rechazado, el motivo y el detalle; publicado con nota, la causa de una reversión (`estado_nota`).
  const motivo = p.motivo_rechazo ? MOTIVO_PERDIDA[p.motivo_rechazo].label : null;
  const titulo = p.estado === "rechazado" ? motivo : p.estado === "publicado" && p.estado_nota ? "Revertido" : null;

  return (
    <div className="flex flex-col gap-4">
      <div className="card">
        <div className="flex flex-wrap items-center gap-2">
          <h2 className="t-h2 min-w-0 flex-1">
            {p.codigo} · {p.nombre}
          </h2>
          <span className={`badge ${estado.badge}`}>{estado.label}</span>
          {!p.activo && <span className="badge badge-neutral">Desactivado</span>}
          {p.arma && <EditarNombre id={p.id} nombre={p.nombre} />}
          {p.estado !== "borrador" && (
            <Link href={`/presupuestos/${p.id}/imprimir`} className="btn btn-secondary btn-sm">
              <Printer size={14} />
              Imprimir
            </Link>
          )}
          {(p.arma || p.revierte) && (
            <AccionesPresupuesto
              id={p.id}
              codigo={p.codigo ?? "El presupuesto"}
              estado={p.estado}
              aprobables={aprobables}
              abiertas={abiertas}
            />
          )}
        </div>
        <p className="t-caption mt-1 flex items-center gap-1">
          <Building2 size={12} className="shrink-0" />
          <Link href={`/obras/${p.obra.id}`} className="truncate underline">
            {p.obra.nombre}
          </Link>
        </p>
        {titulo && (
          <p className="t-body-m mt-3 rounded-md bg-bg-subtle px-3 py-2">
            <span className="font-semibold">{titulo}. </span>
            {p.estado_nota}
          </p>
        )}
      </div>

      {grupos.map(({ variante, versiones, nombre }) => {
        const publicada = versiones.find((v) => v.estado === "publicado");
        const abierta = versiones.find(
          (v) => v.estado === "borrador" || v.estado === "en_revision",
        );
        // Sin publicada, la reemplazada más nueva no la reemplazó nadie: se quitó.
        const quitada = publicada
          ? undefined
          : versiones.find((v) => v.estado === "obsoleto");
        return (
          <div key={variante} className="card">
            <div className="mb-2 flex flex-wrap items-center gap-2">
              <h3 className="t-h3 min-w-0 flex-1">{nombre}</h3>
              {p.arma && (
                <AccionesVariante
                  presupuestoId={p.id}
                  nombre={nombre}
                  publicada={publicada?.id ?? null}
                  abierta={
                    abierta ? { id: abierta.id, numero: abierta.numero } : null
                  }
                  quitable={p.estado === "publicado" && publicadas > 1}
                  descartable={
                    abierta?.estado === "borrador" && p.versiones.length > 1
                  }
                />
              )}
            </div>
            <div className="flex flex-col">
              {versiones.map((v) => {
                const ev = v.id === quitada?.id ? QUITADA : estadoVersion(v, p);
                return (
                  <Link
                    key={v.id}
                    href={`/presupuestos/${p.id}/${v.id}`}
                    className="row flex items-center gap-3 border-b border-border last:border-b-0 hover:bg-bg-subtle"
                  >
                    <div className="min-w-0 flex-1">
                      <p className="t-body-m font-medium text-text-primary">
                        Versión {v.numero}
                      </p>
                      <p className="t-caption">
                        {formatFecha(v.created_at)}
                        {v.estado === "publicado" && v.vence
                          ? ` · vence ${formatFecha(v.vence)}`
                          : ""}
                      </p>
                    </div>
                    <span className={`badge ${ev.badge}`}>{ev.label}</span>
                    <ChevronRight
                      size={16}
                      className="shrink-0 text-text-tertiary"
                    />
                  </Link>
                );
              })}
            </div>
          </div>
        );
      })}
    </div>
  );
}
