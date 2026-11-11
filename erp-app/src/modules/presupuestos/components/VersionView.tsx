import Link from "next/link";
import { Building2, TriangleAlert } from "lucide-react";
import { formatMonto, MONEDAS, type Moneda } from "@/lib/monedas";
import { formatFecha, hoyISO } from "@/lib/utils";
import type { VersionEditor } from "../queries";
import { estadoVersion, formatAlicuota } from "../types";

type Importe = VersionEditor["importes"][number];
type Monto = { importe: number | null; importe_con_iva: number | null };

const TIPO = { catalogo: null, mano: "A mano", minimo: "Mínimo" } as const;

export function VersionView({ datos }: { datos: VersionEditor }) {
  const {
    presupuesto: p,
    version: v,
    secciones,
    renglones,
    importes,
    totales,
  } = datos;
  const estado = estadoVersion(v, p);
  // Con IVA incluido se muestra el importe con IVA que da la base, no uno recalculado acá (*Pantallas*).
  const conIva = !v.iva_discriminado;
  const mostrar = (m: Monto, moneda: Moneda) => {
    const valor = conIva ? m.importe_con_iva : m.importe;
    return valor === null ? null : formatMonto(valor, moneda);
  };
  const delRenglon = new Map(
    importes.filter((i) => i.clave === null).map((i) => [i.renglon_id, i]),
  );
  const vencida =
    v.estado === "publicado" && v.vence !== null && v.vence < hoyISO();

  return (
    <div className="flex flex-col gap-4">
      <div className="card">
        <div className="flex flex-wrap items-center gap-2">
          <h2 className="t-h2 min-w-0 flex-1">
            Versión {v.numero}
            {v.variante_nombre && ` · ${v.variante_nombre}`}
          </h2>
          <span className={`badge ${estado.badge}`}>{estado.label}</span>
        </div>
        <p className="t-caption mt-1">
          <Link href={`/presupuestos/${p.id}`} className="underline">
            {p.codigo} · {p.nombre}
          </Link>
        </p>
        <p className="t-caption mt-1 flex items-center gap-1">
          <Building2 size={12} className="shrink-0" />
          <Link href={`/obras/${p.obra.id}`} className="truncate underline">
            {p.obra.nombre}
          </Link>
        </p>
        <p className="t-caption mt-1">
          {[
            conIva ? "IVA incluido" : "IVA discriminado",
            v.descuento > 0 ? `Descuento ${formatAlicuota(v.descuento)}` : null,
            v.vence && v.estado === "publicado"
              ? `${vencida ? "Venció" : "Vence"} el ${formatFecha(v.vence)}`
              : null,
          ]
            .filter(Boolean)
            .join(" · ")}
        </p>
      </div>

      {secciones.map((s) => {
        const propios = renglones.filter((r) => r.seccion_id === s.id);
        const aparte = [
          ...Map.groupBy(
            importes.filter((i) => i.clave !== null && i.seccion_id === s.id),
            (i) => i.clave,
          ),
        ];
        return (
          <section key={s.id} className="card" aria-label={s.nombre}>
            <div className="mb-2 flex flex-wrap items-baseline gap-x-3">
              <h3 className="t-h3 min-w-0 flex-1">{s.nombre}</h3>
              <span className="t-caption">
                {MONEDAS[s.moneda]} · IVA {formatAlicuota(s.alicuota)}
              </span>
            </div>
            {propios.length === 0 && aparte.length === 0 ? (
              <p className="empty-state empty-state-sm">Sin renglones.</p>
            ) : (
              <ul className="flex flex-col">
                {propios.map((r) => {
                  const i = delRenglon.get(r.id);
                  return (
                    <Fila
                      key={r.id}
                      titulo={r.designacion ?? i?.nombre ?? "—"}
                      detalle={[
                        r.designacion ? i?.nombre : null,
                        r.ubicacion,
                        r.cantidad !== 1
                          ? `${r.cantidad.toLocaleString("es-AR")} u.`
                          : null,
                      ]}
                      etiquetas={[
                        TIPO[r.tipo],
                        r.mantener && r.condiciones_en
                          ? `Precios del ${formatFecha(r.condiciones_en)}`
                          : null,
                      ]}
                      monto={i ? mostrar(i, s.moneda) : null}
                    >
                      {i?.importe === null && r.mensaje && (
                        <p className="t-caption text-warning-text">
                          {r.mensaje}
                        </p>
                      )}
                      {r.mensajes.map((m) => (
                        <p
                          key={m.mensaje}
                          className={`t-caption flex items-start gap-1 ${m.bloquea ? "text-error-text" : "text-warning-text"}`}
                        >
                          <TriangleAlert
                            size={12}
                            className="mt-0.5 shrink-0"
                          />
                          {m.mensaje}
                        </p>
                      ))}
                      {i?.debajo?.map((d) => (
                        <p
                          key={d.clave}
                          className="t-caption flex justify-between gap-3 pl-3"
                        >
                          <span>{d.nombre}</span>
                          <span className="tabular-nums">
                            {mostrar(d, s.moneda)}
                          </span>
                        </p>
                      ))}
                    </Fila>
                  );
                })}
                {aparte.map(([clave, filas]) => (
                  <Fila
                    key={clave}
                    titulo={filas[0].nombre}
                    detalle={[
                      `De ${filas.length} ${filas.length === 1 ? "ventana" : "ventanas"}`,
                    ]}
                    etiquetas={["Aparte"]}
                    monto={mostrar(sumar(filas), s.moneda)}
                  />
                ))}
              </ul>
            )}
          </section>
        );
      })}

      {totales.length > 0 && (
        <section className="card" aria-label="Totales">
          <h3 className="t-h3 mb-2">Totales</h3>
          <div className="flex flex-col gap-4">
            {totales.map((t) => {
              // Con IVA incluido, el descuento es subtotal − total: absorbe el redondeo y el total es el mismo (*Pantallas*).
              const subtotal = conIva
                ? importes
                    .filter((i) => i.moneda === t.moneda)
                    .reduce((s, i) => s + (i.importe_con_iva ?? 0), 0)
                : t.subtotal;
              const descuento = conIva ? subtotal - t.total : t.descuento;
              return (
                <div key={t.moneda} className="flex flex-col gap-1">
                  {totales.length > 1 && (
                    <p className="t-label">{MONEDAS[t.moneda]}</p>
                  )}
                  <Linea
                    texto="Subtotal"
                    valor={formatMonto(subtotal, t.moneda)}
                  />
                  {descuento !== 0 && (
                    <Linea
                      texto={`Descuento ${formatAlicuota(v.descuento)}`}
                      valor={`− ${formatMonto(descuento, t.moneda)}`}
                    />
                  )}
                  {!conIva &&
                    t.iva
                      .filter((x) => x.monto !== 0)
                      .map((x) => (
                        <Linea
                          key={x.alicuota}
                          texto={`IVA ${formatAlicuota(x.alicuota)}`}
                          valor={formatMonto(x.monto, t.moneda)}
                        />
                      ))}
                  <Linea
                    texto={conIva ? "Total con IVA" : "Total"}
                    valor={formatMonto(t.total, t.moneda)}
                    fuerte
                  />
                  {t.sin_precio > 0 && (
                    <p className="alert alert-warning mt-1">
                      {t.sin_precio === 1
                        ? "1 importe sin precio no suma."
                        : `${t.sin_precio} importes sin precio no suman.`}
                    </p>
                  )}
                </div>
              );
            })}
          </div>
        </section>
      )}
    </div>
  );
}

function sumar(filas: Importe[]): Monto {
  const suma = (k: keyof Monto) =>
    filas.some((f) => f[k] === null)
      ? null
      : filas.reduce((s, f) => s + (f[k] ?? 0), 0);
  return { importe: suma("importe"), importe_con_iva: suma("importe_con_iva") };
}

function Fila({
  titulo,
  detalle,
  etiquetas,
  monto,
  children,
}: {
  titulo: string;
  detalle: (string | null | undefined)[];
  etiquetas: (string | null)[];
  monto: string | null;
  children?: React.ReactNode;
}) {
  const texto = detalle.filter(Boolean).join(" · ");
  return (
    <li className="row flex flex-col gap-1 border-b border-border last:border-b-0">
      <div className="flex items-start gap-3">
        <div className="min-w-0 flex-1">
          <p className="t-body-m font-medium text-text-primary">
            {titulo}
            {etiquetas.filter(Boolean).map((e) => (
              <span key={e} className="badge badge-neutral ml-2 align-middle">
                {e}
              </span>
            ))}
          </p>
          {texto && <p className="t-caption">{texto}</p>}
        </div>
        <p
          className={`t-body-m shrink-0 text-right tabular-nums ${monto ? "text-text-primary" : "text-warning-text"}`}
        >
          {monto ?? "Sin precio"}
        </p>
      </div>
      {children}
    </li>
  );
}

function Linea({
  texto,
  valor,
  fuerte,
}: {
  texto: string;
  valor: string;
  fuerte?: boolean;
}) {
  return (
    <p
      className={`flex justify-between gap-3 ${fuerte ? "t-body-l font-semibold text-text-primary" : "t-body-m"}`}
    >
      <span>{texto}</span>
      <span className="tabular-nums">{valor}</span>
    </p>
  );
}
