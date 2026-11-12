import Link from "next/link";
import { Building2, TriangleAlert } from "lucide-react";
import { MOTIVO_PERDIDA } from "@/lib/entes";
import { MONEDAS, formatMontoCliente, type Moneda } from "@/lib/monedas";
import { formatFecha, hoyISO } from "@/lib/utils";
import type { VersionEditor } from "../queries";
import { estadoVersion, estaVencida, formatAlicuota, montoVisible, sumarMontos, type Monto } from "../types";
import { AccionesRenglon, AgregarRenglon } from "./AccionesRenglon";
import { AccionesSeccion, NuevaSeccion } from "./AccionesSeccion";
import { AccionesVersion } from "./AccionesVersion";
import { AntesDePublicar } from "./AntesDePublicar";
import { Condiciones } from "./Condiciones";
import { OpcionalesVentana } from "./Opcionales";
import { Totales } from "./Totales";

const TIPO = { catalogo: null, mano: "A mano", minimo: "Mínimo" } as const;

export function VersionView({
  datos,
  nombres,
  yo,
}: {
  datos: VersionEditor;
  nombres: Record<string, string>;
  yo: string;
}) {
  const {
    presupuesto: p,
    version: v,
    secciones,
    renglones,
    importes,
    totales,
    cargado,
    editable,
    tope,
    paquetes,
    formularios,
    opcionales,
    antes,
  } = datos;
  const ids = secciones.map((s) => s.id);
  const ctx = { versionId: v.id, secciones, paquetes, formularios };
  const formas = Object.fromEntries(
    opcionales.filter((o) => o.como !== "precio").map((o) => [o.clave, o.como]),
  );
  const estado = estadoVersion(v, p);
  const conIva = !v.iva_discriminado;
  const mostrar = (m: Monto, moneda: Moneda) => montoVisible(m, moneda, conIva);
  const delRenglon = new Map(
    importes.filter((i) => i.clave === null).map((i) => [i.renglon_id, i]),
  );
  const vencida = estaVencida(v, hoyISO());

  return (
    <div className="flex flex-col gap-4">
      <div data-tour="presupuestos_version_cabecera" className="card">
        <div className="flex flex-wrap items-center gap-2">
          <h2 className="t-h2 min-w-0 flex-1">
            Versión {v.numero}
            {v.variante_nombre && ` · ${v.variante_nombre}`}
          </h2>
          <span className={`badge ${estado.badge}`}>{estado.label}</span>
          {editable && (
            <AccionesVersion
              version={v}
              tope={tope}
              secciones={secciones}
              opcionales={opcionales}
              renglones={renglones}
            />
          )}
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
        {totales.length > 0 && (
          <p className="mt-3 flex flex-wrap items-baseline gap-x-3 border-t border-border pt-3">
            <span className="t-label flex-1">{conIva ? "Total con IVA" : "Total"}</span>
            {totales.map((t, i) => (
              <span key={t.moneda} className="t-body-l font-semibold tabular-nums text-text-primary">
                {i > 0 && <span className="t-caption mr-3">·</span>}
                {formatMontoCliente(t.total, t.moneda)}
                {t.sin_precio > 0 && <span title="Hay importes sin precio que no suman">*</span>}
              </span>
            ))}
          </p>
        )}
        {antes?.arma && p.obra.estado === "perdida" && (
          <p className="alert alert-warning mt-2 flex items-start gap-2">
            <TriangleAlert size={16} className="mt-0.5 shrink-0" />
            La obra está perdida
            {p.obra.motivo_perdida && ` (${MOTIVO_PERDIDA[p.obra.motivo_perdida].label.toLowerCase()})`}. Al publicar, se
            reabre.
          </p>
        )}
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
          <section key={s.id} data-tour="presupuestos_version_seccion" className="card" aria-label={s.nombre}>
            <div className="mb-2 flex flex-wrap items-center gap-x-3">
              <h3 className="t-h3 min-w-0 flex-1">{s.nombre}</h3>
              <span className="t-caption">
                {MONEDAS[s.moneda]} · IVA {formatAlicuota(s.alicuota)}
              </span>
              {editable && (
                <AccionesSeccion
                  seccion={s}
                  versionId={v.id}
                  ids={ids}
                  conRenglones={
                    propios.length > 0 ||
                    opcionales.some((o) => o.como === s.id)
                  }
                />
              )}
            </div>
            {propios.length === 0 && aparte.length === 0 ? (
              <p className="empty-state empty-state-sm">Sin renglones.</p>
            ) : (
              <ul className="flex flex-col">
                {propios.map((r) => {
                  const i = delRenglon.get(r.id);
                  const formulario =
                    editable && r.paquete_id
                      ? formularios[r.paquete_id]
                      : null;
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
                      cargado={cargado[r.id]}
                      monto={i ? mostrar(i, s.moneda) : null}
                      acciones={
                        editable
                          ? (cabecera) => (
                              <AccionesRenglon {...ctx} renglon={r} nombre={i?.nombre ?? r.descripcion ?? "—"}>
                                {cabecera}
                              </AccionesRenglon>
                            )
                          : undefined
                      }
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
                      {formulario ? (
                        <OpcionalesVentana
                          versionId={v.id}
                          renglon={r}
                          formulario={formulario}
                          formas={formas}
                          montos={Object.fromEntries(
                            (i?.debajo ?? []).map((d) => [
                              d.clave,
                              mostrar(d, s.moneda),
                            ]),
                          )}
                        />
                      ) : (
                        i?.debajo?.map((d) => (
                          <p
                            key={d.clave}
                            className="t-caption flex justify-between gap-3 pl-3"
                          >
                            <span>{d.nombre}</span>
                            <span className="tabular-nums">
                              {mostrar(d, s.moneda)}
                            </span>
                          </p>
                        ))
                      )}
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
                    monto={mostrar(sumarMontos(filas), s.moneda)}
                  />
                ))}
              </ul>
            )}
            {editable && <AgregarRenglon {...ctx} seccionId={s.id} />}
          </section>
        );
      })}

      {editable && <NuevaSeccion versionId={v.id} secciones={secciones} />}

      {totales.length > 0 && (
        <section data-tour="presupuestos_version_totales" className="card" aria-label="Totales">
          <h3 className="t-h3 mb-2">Totales</h3>
          <Totales totales={totales} importes={importes} conIva={conIva} descuento={v.descuento} />
        </section>
      )}

      {(v.condiciones || datos.terminos) && (
        <section className="card flex flex-col gap-3" aria-label="Condiciones">
          <Condiciones particulares={v.condiciones} generales={datos.terminos} />
        </section>
      )}

      {/* Al final: arriba, cada edición le cambia el alto y el navegador corre el scroll, que cierra los menús abiertos. */}
      {antes && (v.estado === "borrador" || v.estado === "en_revision") && (
        <AntesDePublicar
          versionId={v.id}
          numero={v.numero}
          estado={v.estado}
          antes={antes}
          nombres={nombres}
          yo={yo}
        />
      )}
    </div>
  );
}

function Fila({
  titulo,
  detalle,
  cargado,
  etiquetas,
  monto,
  acciones,
  children,
}: {
  titulo: string;
  detalle: (string | null | undefined)[];
  // Medidas, color y lo elegido: para controlar la carga contra el plano sin abrir cada ventana.
  cargado?: string | null;
  etiquetas: (string | null)[];
  monto: string | null;
  // Recibe el encabezado de la fila, que al tocarlo edita (`AccionesRenglon`).
  acciones?: (cabecera: React.ReactNode) => React.ReactNode;
  children?: React.ReactNode;
}) {
  const texto = detalle.filter(Boolean).join(" · ");
  const cabecera = (
    <>
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
        {cargado && <p className="t-caption">{cargado}</p>}
      </div>
      <p className={`t-body-m shrink-0 text-right tabular-nums ${monto ? "text-text-primary" : "text-warning-text"}`}>
        {monto ?? "Sin precio"}
      </p>
    </>
  );
  return (
    <li className="row flex flex-col gap-1 border-b border-border last:border-b-0">
      <div className="flex items-start gap-3">{acciones ? acciones(cabecera) : cabecera}</div>
      {children}
    </li>
  );
}
