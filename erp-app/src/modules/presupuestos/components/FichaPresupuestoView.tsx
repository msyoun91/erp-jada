import Link from "next/link";
import { Building2, ChevronRight } from "lucide-react";
import { ENTES } from "@/lib/entes";
import { formatFecha } from "@/lib/utils";
import type { FichaPresupuesto } from "../queries";
import { estadoVersion } from "../types";
import { AccionesVariante, EditarNombre } from "./AccionesFicha";

const QUITADA = { label: "Quitada", badge: "badge-neutral" };

export function FichaPresupuestoView({
  presupuesto: p,
}: {
  presupuesto: FichaPresupuesto;
}) {
  const variantes = Map.groupBy(p.versiones, (v) => v.variante);
  const estado = ENTES.presupuesto.estados[p.estado];
  const publicadas = p.versiones.filter((v) => v.estado === "publicado").length;

  return (
    <div className="flex flex-col gap-4">
      <div className="card">
        <div className="flex flex-wrap items-center gap-2">
          <h2 className="t-h2 min-w-0 flex-1">
            {p.codigo} · {p.nombre}
          </h2>
          <span className={`badge ${estado.badge}`}>{estado.label}</span>
          {p.arma && <EditarNombre id={p.id} nombre={p.nombre} />}
        </div>
        <p className="t-caption mt-1 flex items-center gap-1">
          <Building2 size={12} className="shrink-0" />
          <Link href={`/obras/${p.obra.id}`} className="truncate underline">
            {p.obra.nombre}
          </Link>
        </p>
        {p.estado === "rechazado" && p.estado_nota && (
          <p className="t-body-m mt-2">{p.estado_nota}</p>
        )}
      </div>

      {[...variantes].sort(([a], [b]) => a - b).map(([variante, versiones]) => {
        const nombre =
          versiones.find((v) => v.variante_nombre)?.variante_nombre ??
          (variantes.size > 1 ? `Variante ${variante}` : "Presupuesto");
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
