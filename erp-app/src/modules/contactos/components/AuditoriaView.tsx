import Link from "next/link";
import { X } from "lucide-react";
import { FiltroDias } from "@/components/ui/FiltroDias";
import { formatFechaHora } from "@/lib/utils";
import type { AccesoAuditado } from "../queries";
import { FiltroPersona } from "./FiltroPersona";

const TOPE = 500;

type Resumen = { usuario_id: string; usuario: string; accesos: number; personas: number };

function url({ dias, usuario, persona }: { dias?: number; usuario?: string | null; persona?: string | null }) {
  const q = new URLSearchParams();
  if (dias) q.set("dias", String(dias));
  if (usuario) q.set("usuario", usuario);
  if (persona) q.set("persona", persona);
  const s = q.toString();
  return s ? `/contactos/auditoria?${s}` : "/contactos/auditoria";
}

function Chip({ label, quitar }: { label: string; quitar: string }) {
  return (
    <span className="badge badge-info inline-flex items-center gap-1">
      {label}
      <Link href={quitar} aria-label={`Quitar ${label}`} className="tap-target inline-flex items-center">
        <X size={12} strokeWidth={2} />
      </Link>
    </span>
  );
}

function plural(n: number, uno: string, varios: string) {
  return `${n} ${n === 1 ? uno : varios}`;
}

// Quién miró teléfono o email de qué persona: nombres y fechas, nunca el dato.
// La señal es mirar muchas que no son suyas (`decisiones/contactos.md`).
export function AuditoriaView({
  dias,
  usuario,
  persona,
  resumen,
  detalle,
}: {
  dias: number;
  usuario: string | null;
  persona: string | null;
  resumen: Resumen[];
  detalle: AccesoAuditado[] | null;
}) {
  const filas = detalle?.slice(0, TOPE) ?? [];
  const hayMas = (detalle?.length ?? 0) > TOPE;
  const nombreUsuario = resumen.find((r) => r.usuario_id === usuario)?.usuario ?? filas[0]?.usuario ?? "Usuario";
  const nombrePersona = filas[0]?.persona ?? "Persona elegida";
  const ajenas = new Set(filas.filter((f) => f.dueno_id !== f.usuario_id).map((f) => f.persona_id)).size;
  const distintas = new Set(filas.map((f) => f.persona_id)).size;

  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-wrap items-center gap-3">
        <FiltroDias href={url({ usuario, persona })} dias={dias} etiqueta="Período" />
        {usuario && <Chip label={nombreUsuario} quitar={url({ dias, persona })} />}
        {persona ? (
          <Chip label={nombrePersona} quitar={url({ dias, usuario })} />
        ) : (
          <FiltroPersona base={url({ dias, usuario })} />
        )}
      </div>

      <div className="grid gap-4 lg:grid-cols-2 lg:items-start">
        <section className="flex flex-col gap-2">
          <h2 className="t-h3">Quién miró contactos</h2>
          {resumen.length === 0 ? (
            <div className="empty-state">
              <p className="t-body-m">Nadie miró un teléfono o email en los últimos {dias} días.</p>
            </div>
          ) : (
            <ul className="flex flex-col rounded-lg border border-border bg-bg-surface">
              {resumen.map((r) => {
                const elegido = r.usuario_id === usuario;
                return (
                  <li key={r.usuario_id} className="border-b border-border last:border-b-0">
                    <Link
                      href={url({ dias, usuario: elegido ? null : r.usuario_id, persona })}
                      aria-current={elegido ? "true" : undefined}
                      className={`row flex items-center gap-3 ${elegido ? "bg-brand-50" : "hover:bg-bg-subtle"}`}
                    >
                      <span className="t-body-m min-w-0 flex-1 truncate font-medium text-text-primary">
                        {r.usuario}
                      </span>
                      <span className="t-caption shrink-0">
                        {plural(r.accesos, "acceso", "accesos")} · {plural(r.personas, "persona", "personas")}
                      </span>
                    </Link>
                  </li>
                );
              })}
            </ul>
          )}
        </section>

        <section className="flex flex-col gap-2">
          <h2 className="t-h3">
            {usuario && persona
              ? `${nombreUsuario} y ${nombrePersona}`
              : usuario
                ? `Lo que miró ${nombreUsuario}`
                : persona
                  ? `Quién miró a ${nombrePersona}`
                  : "Detalle"}
          </h2>
          {!detalle ? (
            <p className="t-body-m text-text-tertiary">
              Tocá un usuario para ver a quién miró, o filtrá por persona para ver quién la miró.
            </p>
          ) : filas.length === 0 ? (
            <div className="empty-state">
              <p className="t-body-m">Sin accesos en los últimos {dias} días.</p>
            </div>
          ) : (
            <>
              {usuario && !persona && (
                <p className="t-body-m">
                  {plural(distintas, "persona", "personas")}
                  {ajenas > 0 ? `, ${ajenas} que no ${ajenas === 1 ? "era suya" : "eran suyas"}` : ", todas suyas"}.
                </p>
              )}
              <ul className="flex flex-col rounded-lg border border-border bg-bg-surface">
                {filas.map((f, i) => (
                  <li
                    key={`${f.usuario_id}-${f.persona_id}-${f.created_at}-${i}`}
                    className="row flex items-center gap-3 border-b border-border last:border-b-0"
                  >
                    <div className="min-w-0 flex-1">
                      <p className="t-body-m truncate font-medium text-text-primary">
                        {usuario ? f.persona : f.usuario}
                      </p>
                      <p className="t-caption truncate">
                        {formatFechaHora(f.created_at)} · {f.dueno_id === f.usuario_id ? "suya" : `de ${f.dueno}`}
                      </p>
                    </div>
                    {f.dueno_id !== f.usuario_id && <span className="badge badge-warning shrink-0">No era suya</span>}
                  </li>
                ))}
              </ul>
              {hayMas && (
                <p className="t-caption text-text-tertiary">
                  Se muestran los {TOPE} más recientes y hay más: acotá el período o filtrá por persona.
                </p>
              )}
            </>
          )}
        </section>
      </div>
    </div>
  );
}
