"use client";

import Link from "next/link";
import { ArrowLeft, CircleCheck, TriangleAlert } from "lucide-react";
import type { Moneda } from "@/lib/monedas";
import { formatFechaHora } from "@/lib/utils";
import { ACCION_VERSION, ESTADO_VERSION } from "../etiquetas";
import type {
  Caso,
  CasoCalculado,
  Categoria,
  Contenido,
  Despiece,
  InsumoBasico,
  Oferta,
  PrecioDetalle,
  Version,
} from "../types";
import { Calculadora } from "./Calculadora";
import { VersionAcciones } from "./VersionAcciones";

// La ruta de los avisos de una versión (`/catalogo/paquetes/versiones/<id>`). La vista sola muestra el
// despiece sin precio ni botones; armar y aprobar suman lo suyo.
export function VersionView({
  version,
  contenido,
  categorias,
  insumos,
  frena,
  oferta,
  casos,
  inicial,
  puedeArmar,
  puedeAprobar,
  monedaPrincipal,
}: {
  version: Version;
  contenido: Contenido;
  categorias: Categoria[];
  insumos: InsumoBasico[];
  frena: string[] | null;
  oferta: Oferta[];
  casos: CasoCalculado[];
  inicial: { caso: Caso | null; resultado: Despiece | null; comparado: PrecioDetalle | null };
  puedeArmar: boolean;
  puedeAprobar: boolean;
  monedaPrincipal: Moneda;
}) {
  const { paquete } = version;
  const categoria = categorias.find((c) => c.id === version.categoria_id);
  const publicada = paquete.versiones.find((v) => v.estado === "publicado") ?? null;
  const ultima = version.historia[0];
  const comparar =
    version.estado === "en_revision" && publicada ? { id: publicada.id, numero: publicada.numero } : null;
  const nombreInsumo = new Map(insumos.map((i) => [i.id, i.nombre]));

  return (
    <div className="flex flex-col gap-6">
      <Link href="/catalogo/paquetes" className="t-body-m flex items-center gap-1 text-text-brand">
        <ArrowLeft size={14} strokeWidth={1.75} />
        Paquetes
      </Link>

      <section className="flex flex-col gap-3">
        <div className="flex flex-wrap items-center gap-2">
          <h2 className="t-h2">
            {version.nombre} · v{version.numero}
          </h2>
          <span className={`badge ${ESTADO_VERSION[version.estado].badge}`}>
            {ESTADO_VERSION[version.estado].label}
          </span>
          {!paquete.activo && <span className="badge badge-neutral">Paquete de baja</span>}
        </div>
        <p className="t-body-m">
          {[
            categoria?.nombre,
            version.colores.length > 0
              ? `Colores: ${version.colores.map((c) => (c.base ? `${c.nombre} (base)` : c.nombre)).join(", ")}`
              : "Sin colores",
            !paquete.activo && `De baja por ${paquete.baja_por ?? "decisión de Técnica"}`,
          ]
            .filter(Boolean)
            .join(" · ")}
        </p>
        {paquete.versiones.length > 1 && (
          <nav aria-label="Versiones del paquete" className="flex flex-wrap gap-2">
            {paquete.versiones.map((v) =>
              v.id === version.id ? (
                <span key={v.id} className="badge badge-info">
                  v{v.numero} · {ESTADO_VERSION[v.estado].label}
                </span>
              ) : (
                <Link key={v.id} href={`/catalogo/paquetes/versiones/${v.id}`} className="badge badge-neutral">
                  v{v.numero} · {ESTADO_VERSION[v.estado].label}
                </Link>
              ),
            )}
          </nav>
        )}
        {version.estado === "borrador" && ultima?.accion === "devuelta" && (
          <div className="rounded-md bg-warning-bg p-3 text-warning-text">
            <p className="t-body-m font-semibold">Devuelta{ultima.quien ? ` por ${ultima.quien}` : ""}</p>
            <p className="t-body-m">{ultima.motivo}</p>
          </div>
        )}
        <VersionAcciones
          version={version}
          frena={frena ?? []}
          publicada={publicada}
          puedeArmar={puedeArmar}
          puedeAprobar={puedeAprobar}
        />
      </section>

      {frena && (
        <section className="flex flex-col gap-1">
          <h3 className="t-label">Lo que frena el envío</h3>
          {frena.length === 0 ? (
            <p className="t-body-m flex items-center gap-2 text-success-text">
              <CircleCheck size={16} strokeWidth={1.75} />
              Nada: se puede enviar.
            </p>
          ) : (
            <ul className="flex flex-col gap-1">
              {frena.map((f) => (
                <li key={f} className="t-body-m flex items-start gap-2 text-warning-text">
                  <TriangleAlert size={16} strokeWidth={1.75} className="mt-0.5 shrink-0" />
                  {f}
                </li>
              ))}
            </ul>
          )}
        </section>
      )}

      <section className="flex flex-col gap-3">
        <h3 className="t-label">{puedeAprobar ? "Despiece y precio" : "Despiece"}</h3>
        {comparar && (
          <p className="t-caption">
            Junto a la v{comparar.numero} publicada, con las mismas medidas y la misma fecha: la diferencia sale solo de
            la versión.
          </p>
        )}
        <Calculadora
          versionId={version.id}
          contenido={contenido}
          colores={version.colores}
          nombreInsumo={nombreInsumo}
          inicial={inicial}
          puedeAprobar={puedeAprobar}
          monedaPrincipal={monedaPrincipal}
          comparar={comparar}
        />
      </section>

      <section className="flex flex-col gap-2">
        <h3 className="t-label">Casos de prueba</h3>
        {casos.length === 0 ? (
          <p className="t-body-m text-warning-text">Sin casos: la versión no se puede enviar sin al menos uno.</p>
        ) : (
          <ul className="flex flex-col rounded-lg border border-border bg-bg-surface">
            {casos.map((c) => (
              <li key={c.caso_id} className="row flex flex-col gap-0.5 border-b border-border last:border-b-0">
                <p className="t-body-m font-medium">{c.nombre}</p>
                {c.resultado.calculable ? (
                  <p className="t-caption">
                    Se calcula{c.resultado.bloqueado ? " · con un bloqueo" : ""}
                    {c.resultado.mensajes.length > 0
                      ? ` · ${c.resultado.mensajes.map((m) => m.mensaje).join(" · ")}`
                      : ""}
                  </p>
                ) : (
                  <p className="t-caption text-error-text">{c.resultado.errores.join(" · ")}</p>
                )}
              </li>
            ))}
          </ul>
        )}
      </section>

      <section className="flex flex-col gap-2">
        <h3 className="t-label">Qué se ofrece en cada color</h3>
        <ul className="flex flex-col rounded-lg border border-border bg-bg-surface">
          {oferta.map((o) => (
            <li
              key={o.color_id ?? "sin-color"}
              className="row flex flex-col gap-0.5 border-b border-border last:border-b-0"
            >
              <p className="t-body-m font-medium">
                {o.color ?? "Sin color"}: {o.armable ? "se ofrece" : "no se ofrece"}
              </p>
              {[
                o.piezas_fuera.length > 0 && `Sin ${o.piezas_fuera.join(", ")}`,
                o.opciones_fuera.length > 0 && `No se ofrece: ${o.opciones_fuera.join(", ")}`,
                o.faltan.length > 0 && `Falta: ${o.faltan.join(", ")}`,
              ]
                .filter(Boolean)
                .map((t) => (
                  <p key={t as string} className="t-caption">
                    {t}
                  </p>
                ))}
            </li>
          ))}
        </ul>
      </section>

      {version.historia.length > 0 && (
        <section className="flex flex-col gap-2">
          <h3 className="t-label">Historia de la v{version.numero}</h3>
          <ul className="flex flex-col">
            {version.historia.map((h) => (
              <li key={h.id} className="border-b border-border py-2 last:border-b-0">
                <p className="t-body-m">
                  {ACCION_VERSION[h.accion]}
                  {h.motivo ? `: ${h.motivo}` : ""}
                </p>
                <p className="t-caption">{[h.quien, formatFechaHora(h.created_at)].filter(Boolean).join(" · ")}</p>
              </li>
            ))}
          </ul>
        </section>
      )}
    </div>
  );
}
