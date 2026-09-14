import Link from "next/link";
import { Plus } from "lucide-react";
import { BADGE_ESTADO_TAREA, LABEL_ESTADO_TAREA, type TareaRelacionada } from "@/lib/tareas";
import { formatFecha } from "@/lib/utils";

// Las tareas relacionadas con esta ficha (sql/059). Tareas es otro módulo: la
// fila y "Nueva tarea" llevan a su Lista por link (`?tarea=`, `?nueva=`), sin
// importar sus componentes.
export function TareasRelacionadas({
  ente,
  registroId,
  tareas,
}: {
  ente: "obra" | "empresa" | "persona";
  registroId: string;
  tareas: TareaRelacionada[];
}) {
  return (
    <section>
      <div className="mb-2 flex items-center gap-2">
        <h3 className="t-h3 flex-1">Tareas</h3>
        <Link href={`/tareas?nueva=${ente}:${registroId}`} className="btn btn-secondary btn-sm">
          <Plus size={14} />
          Nueva tarea
        </Link>
      </div>
      {tareas.length === 0 ? (
        <div className="empty-state p-8">
          <p className="t-body-m">Ninguna tarea relacionada todavía.</p>
        </div>
      ) : (
        <ul className="flex flex-col gap-2">
          {tareas.map((t) => (
            <li key={t.id} className="card p-3">
              <Link href={`/tareas?tarea=${t.id}`} className="t-body-m block truncate font-semibold hover:underline">
                {t.titulo}
              </Link>
              <div className="mt-0.5 flex flex-wrap items-center gap-x-2 gap-y-1">
                <span className={`badge ${BADGE_ESTADO_TAREA[t.estado]}`}>{LABEL_ESTADO_TAREA[t.estado]}</span>
                {t.fecha_vencimiento && <span className="t-caption">Vence {formatFecha(t.fecha_vencimiento)}</span>}
                {t.responsable && <span className="t-caption">{t.responsable}</span>}
                {(t.proyecto || t.hilo) && (
                  <span className="t-caption">{[t.proyecto, t.hilo].filter(Boolean).join(" · ")}</span>
                )}
              </div>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}
