import Link from "next/link";
import { ChevronRight, CircleCheck, TriangleAlert, UserRound } from "lucide-react";
import { Vacio } from "@/components/ui/Vacio";
import { hace } from "@/lib/utils";
import type { RevisionPendiente } from "../queries";

// La cola de Técnica: una fila por versión, con las ventanas que esperan (decisiones/presupuestos.md → *Pantallas*).
export function RevisionView({ pendientes }: { pendientes: RevisionPendiente[] }) {
  if (pendientes.length === 0) {
    return (
      <Vacio icono={CircleCheck} color="text-success" titulo="Nada espera tu revisión">
        Cuando un presupuesto tenga una ventana con alertas, te llega un aviso y aparece acá.
      </Vacio>
    );
  }
  return (
    <div data-tour="presupuestos_revision_lista" className="flex flex-col rounded-lg border border-border bg-bg-surface">
      {pendientes.map((p) => (
        <Link
          key={p.version_id}
          href={`/presupuestos/revision/${p.version_id}`}
          className="row flex items-center gap-3 border-b border-border last:border-b-0 hover:bg-bg-subtle"
        >
          <div className="flex min-w-0 flex-1 flex-col gap-1">
            <div className="flex flex-wrap items-baseline gap-x-3">
              <p className="t-body-m min-w-0 flex-1 font-medium text-text-primary">
                {p.codigo} · v{p.version}
              </p>
              <p className="t-caption flex items-center gap-1">
                <UserRound size={12} className="shrink-0" />
                {p.pedido_por_nombre} · {hace(p.pedido_en)}
              </p>
            </div>
            <ul className="flex flex-col gap-0.5">
              {p.ventanas.map((v) => (
                <li key={v.pedido_id} className="t-caption flex items-start gap-1">
                  <TriangleAlert size={12} className="mt-0.5 shrink-0 text-warning-text" />
                  <span>
                    <span className="font-medium text-text-primary">{v.etiqueta}</span> — {v.motivos.join("; ")}
                  </span>
                </li>
              ))}
            </ul>
          </div>
          <ChevronRight size={16} className="shrink-0 text-text-tertiary" />
        </Link>
      ))}
    </div>
  );
}
