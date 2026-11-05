"use client";

import { CircleAlert, TriangleAlert } from "lucide-react";
import { formatMonto } from "@/lib/monedas";
import { POR_UNIDAD, textoFila, textoMedida, textoPorcentaje } from "../etiquetas";
import type { Despiece, FilaDespiece, PrecioDetalle } from "../types";

function esPrecio(d: Despiece): d is PrecioDetalle {
  return "sin_precio" in d;
}

const clave = (f: FilaDespiece) => `${f.pieza}|${f.material}|${f.insumo}`;

// Lo que ve quien revisa cortes, y con `catalogo_aprobar` también el precio. Con `comparado` (la publicada con
// la misma entrada y fecha) se marcan las filas que cambian: un `ancho − 20` por `ancho − 2` da otro total.
export function DespieceResultado({
  resultado,
  comparado,
  numeroComparado,
}: {
  resultado: Despiece;
  comparado: PrecioDetalle | null;
  numeroComparado: number | null;
}) {
  const totalAntes = new Map(comparado?.filas.map((f) => [clave(f), f.total]) ?? []);
  const claves = new Set(resultado.filas.map(clave));
  const soloAntes = comparado?.filas.filter((f) => !claves.has(clave(f))) ?? [];
  const precio = esPrecio(resultado) ? resultado : null;

  return (
    <div className="flex flex-col gap-4">
      {resultado.errores.length > 0 && (
        <div className="alert alert-error">
          <p className="font-semibold">{resultado.mensaje ?? "No se puede calcular"}</p>
          <ul className="mt-1 list-disc pl-5">
            {resultado.errores.map((e) => (
              <li key={e}>{e}</li>
            ))}
          </ul>
        </div>
      )}

      {resultado.mensajes.length > 0 && (
        <ul className="flex flex-col gap-1">
          {resultado.mensajes.map((m, i) => (
            <li
              key={`${m.mensaje}-${i}`}
              className={`t-body-m flex items-start gap-2 ${m.bloquea ? "text-error-text" : "text-warning-text"}`}
            >
              {m.bloquea ? (
                <CircleAlert size={16} className="mt-0.5 shrink-0" />
              ) : (
                <TriangleAlert size={16} className="mt-0.5 shrink-0" />
              )}
              {m.bloquea ? "Bloquea: " : ""}
              {m.mensaje}
            </li>
          ))}
        </ul>
      )}

      {precio && <Precio precio={precio} comparado={comparado} numeroComparado={numeroComparado} />}

      {resultado.variables.length > 0 && (
        <section>
          <h4 className="t-label mb-1">Variables</h4>
          <p className="t-body-m">
            {resultado.variables
              .map((v) => `${v.nombre} = ${typeof v.valor === "number" ? textoMedida(v.valor) : v.valor}`)
              .join(" · ")}
          </p>
        </section>
      )}

      {resultado.piezas.map((p) => (
        <section key={p.id}>
          <h4 className="t-body-m font-semibold">
            {[
              `${p.nombre} × ${textoMedida(p.cantidad)}`,
              p.peso !== undefined && `${textoMedida(p.peso)} kg c/u`,
              p.espesor !== undefined && `espesor ${textoMedida(p.espesor)} mm`,
              precio && p.subtotal !== undefined && formatMonto(p.subtotal, precio.moneda),
            ]
              .filter(Boolean)
              .join(" · ")}
          </h4>
          <ul className="flex flex-col">
            {resultado.filas
              .filter((f) => f.pieza_id === p.id)
              .map((f) => {
                const antes = totalAntes.get(clave(f));
                const cambio = comparado && antes !== f.total;
                return (
                  <li
                    key={`${f.material_id}-${f.opcion_id ?? ""}`}
                    className="flex items-baseline justify-between gap-2 border-b border-border py-1.5 last:border-b-0"
                  >
                    <div className="min-w-0">
                      <p className="t-body-m">
                        {f.material !== f.insumo ? `${f.material}: ` : ""}
                        {f.insumo}
                        {f.color ? ` · ${f.color}` : ""}
                      </p>
                      <p className="t-caption">
                        {textoFila(f)}
                        {cambio &&
                          (antes === undefined
                            ? ` · nuevo en esta versión`
                            : ` · en v${numeroComparado}: ${textoMedida(antes)}`)}
                      </p>
                    </div>
                    {precio && (
                      <span className="t-caption shrink-0 text-right">
                        {f.costo !== undefined && f.costo_moneda
                          ? `${formatMonto(f.costo, f.costo_moneda)} /${POR_UNIDAD[f.unidad]}`
                          : "sin costo"}
                        <br />
                        {f.importe !== undefined ? formatMonto(f.importe, precio.moneda) : "—"}
                      </span>
                    )}
                    {cambio && <span className="badge badge-warning shrink-0">Cambia</span>}
                  </li>
                );
              })}
          </ul>
        </section>
      ))}

      {soloAntes.length > 0 && (
        <section>
          <h4 className="t-label mb-1">Solo en v{numeroComparado}</h4>
          <ul className="t-body-m list-disc pl-5">
            {soloAntes.map((f) => (
              <li key={`${f.material_id}-${f.opcion_id ?? ""}`}>
                {f.pieza} · {f.insumo}: {textoFila(f)}
              </li>
            ))}
          </ul>
        </section>
      )}
    </div>
  );
}

function Precio({
  precio,
  comparado,
  numeroComparado,
}: {
  precio: PrecioDetalle;
  comparado: PrecioDetalle | null;
  numeroComparado: number | null;
}) {
  const m = (n: number | null | undefined) => (n === null || n === undefined ? "—" : formatMonto(n, precio.moneda));
  return (
    <section className="card flex flex-col gap-2">
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <span className="t-h2">{precio.precio === null ? "Sin precio" : m(precio.precio)}</span>
        {comparado && (
          <span className="t-body-m">
            v{numeroComparado}: {comparado.precio === null ? "sin precio" : m(comparado.precio)}
          </span>
        )}
      </div>
      <p className="t-caption">Sin IVA. Con los costos, los % y el tipo de cambio de hoy.</p>
      {precio.sin_precio.length > 0 && (
        <ul className="t-body-m list-disc pl-5 text-error-text">
          {precio.sin_precio.map((s) => (
            <li key={s}>{s}</li>
          ))}
        </ul>
      )}
      <dl className="t-body-m grid grid-cols-[1fr_auto] gap-x-4 gap-y-1">
        <dt>Costo del despiece</dt>
        <dd className="text-right">{m(precio.costo_despiece)}</dd>
        {precio.servicios
          .filter((s) => s.paso === 1)
          .map((s) => (
            <ServicioFila key={s.porcentaje_id} s={s} m={m} />
          ))}
        <dt className="font-semibold">Subtotal</dt>
        <dd className="text-right font-semibold">{m(precio.subtotal)}</dd>
        {precio.servicios
          .filter((s) => s.paso > 1)
          .map((s) => (
            <ServicioFila key={s.porcentaje_id} s={s} m={m} />
          ))}
        <dt className="font-semibold">Precio de venta</dt>
        <dd className="text-right font-semibold">{m(precio.precio)}</dd>
      </dl>
    </section>
  );
}

function ServicioFila({
  s,
  m,
}: {
  s: PrecioDetalle["servicios"][number];
  m: (n: number | null | undefined) => string;
}) {
  return (
    <>
      <dt className={s.aplica ? "" : "text-text-tertiary"}>
        {s.nombre} {textoPorcentaje(s.porcentaje)}
        <span className="t-caption block">
          {[
            `paso ${s.paso}`,
            s.categorias.length > 0 ? `sobre ${s.categorias.join(", ")}` : null,
            s.aplica ? `base ${m(s.base)}` : s.opcional ? "opcional, sin elegir" : "no aplica",
            s.minimo_convertido !== undefined && `mínimo ${m(s.minimo_convertido)} por ${s.minimo_por}`,
          ]
            .filter(Boolean)
            .join(" · ")}
        </span>
      </dt>
      <dd className="text-right">{m(s.monto)}</dd>
    </>
  );
}
