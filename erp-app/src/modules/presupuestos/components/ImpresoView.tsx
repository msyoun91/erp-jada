import Image from "next/image";
import { formatMontoCliente, simboloCliente } from "@/lib/monedas";
import { formatFecha } from "@/lib/utils";
import { EMPRESA } from "../empresa";
import type { Impreso } from "../queries";
import { formatAlicuota, montoVisible, sumarMontos, type Monto } from "../types";
import { Totales } from "./Totales";

type Version = Impreso["versiones"][number];

// Lo que recibe el cliente: lo publicado, sin costos, alertas, mantener ni comparación (*El cliente y el portal*). Lo que va
// debajo de una ventana, solo lo elegido (*Secciones y opcionales*).
export function ImpresoView({ impreso, clientes, hoy }: { impreso: Impreso; clientes: string[]; hoy: string }) {
  const { presupuesto: p, versiones } = impreso;
  const nombre = (v: Version) => v.version.variante_nombre ?? (versiones.length > 1 ? `Variante ${v.version.variante}` : null);
  const total = (v: Version) => v.totales.map((t) => formatMontoCliente(t.total, t.moneda)).join(" + ");

  return (
    <article className="card mx-auto w-full max-w-[820px] print:max-w-none print:rounded-none print:border-0 print:p-0">
      <header className="flex flex-wrap items-start justify-between gap-4 border-b border-border pb-4">
        <div>
          <Image src={EMPRESA.logo} alt={EMPRESA.nombre} width={96} height={35} className="logo mb-2" />
          {EMPRESA.lineas.map((l) => (
            <p key={l} className="t-caption">
              {l}
            </p>
          ))}
        </div>
        <div className="text-right">
          <p className="t-label">Presupuesto</p>
          <p className="t-h3">{p.codigo}</p>
          <p className="t-caption">{formatFecha(hoy)}</p>
        </div>
      </header>

      <section aria-label="Cliente" className="border-b border-border py-4">
        <p className="t-label mb-1">Cliente</p>
        <p className="t-body-m font-medium text-text-primary">{p.obra.nombre}</p>
        <p className="t-caption">{[p.obra.direccion, p.obra.localidad].filter(Boolean).join(", ")}</p>
        {clientes.length > 0 && <p className="t-caption">{clientes.join(" · ")}</p>}
      </section>

      <h2 className="t-h2 mt-4">{p.nombre}</h2>
      {versiones.length > 1 && (
        <p className="t-body-m mt-1">{versiones.map((v) => `${nombre(v)} ${total(v)}`).join(" · ")}</p>
      )}

      {versiones.map((v) => (
        <VersionImpresa key={v.version.id} v={v} nombre={nombre(v)} />
      ))}
    </article>
  );
}

function VersionImpresa({ v, nombre }: { v: Version; nombre: string | null }) {
  const conIva = !v.version.iva_discriminado;
  const delRenglon = new Map(v.importes.filter((i) => i.clave === null).map((i) => [i.renglon_id, i]));
  return (
    <section aria-label={nombre ?? "Presupuesto"} className="mt-6">
      <div className="flex flex-wrap items-baseline gap-x-3 border-b border-border-strong pb-1 print:break-after-avoid">
        {nombre && <h3 className="t-h3 min-w-0 flex-1">{nombre}</h3>}
        <p className="t-caption ml-auto">
          {[conIva ? "IVA incluido" : "IVA discriminado", v.version.vence && `Válido hasta el ${formatFecha(v.version.vence)}`]
            .filter(Boolean)
            .join(" · ")}
        </p>
      </div>

      {v.secciones.map((s) => {
        const propios = v.renglones.filter((r) => r.seccion_id === s.id);
        const aparte = Map.groupBy(
          v.importes.filter((i) => i.clave !== null && i.seccion_id === s.id),
          (i) => i.clave ?? "",
        );
        // El mínimo de un opcional que va aparte se suma a su renglón: el cliente ve una sola Colocación (*Secciones y
        // opcionales*).
        const sumados = new Set<string>();
        const montos = new Map<string, Monto[]>([...aparte].map(([clave, filas]) => [clave, [...filas]]));
        for (const r of propios) {
          const i = delRenglon.get(r.id);
          const clave = `servicio:${r.porcentaje_id}`;
          if (r.tipo === "minimo" && i && montos.has(clave)) {
            montos.get(clave)?.push(i);
            sumados.add(r.id);
          }
        }
        return (
          <div key={s.id} className="mt-4">
            <div className="flex flex-wrap items-baseline gap-x-3 print:break-after-avoid">
              <h4 className="t-body-m min-w-0 flex-1 font-semibold text-text-primary">{s.nombre}</h4>
              <span className="t-caption">
                {simboloCliente(s.moneda)} · IVA {formatAlicuota(s.alicuota)}
              </span>
            </div>
            <ul className="flex flex-col">
              {propios
                .filter((r) => !sumados.has(r.id))
                .map((r) => {
                  const i = delRenglon.get(r.id);
                  const titulo = r.tipo === "minimo" ? `Mínimo de ${i?.nombre ?? r.descripcion}` : (r.designacion ?? i?.nombre ?? "—");
                  return (
                    <Renglon
                      key={r.id}
                      titulo={titulo}
                      detalle={[
                        r.designacion ? i?.nombre : null,
                        r.ubicacion,
                        r.cantidad !== 1 ? `${r.cantidad.toLocaleString("es-AR")} u.` : null,
                      ]}
                      cargado={v.cargado[r.id] ?? null}
                      monto={i ? montoVisible(i, s.moneda, conIva) : null}
                    >
                      {i?.debajo?.map((d) => (
                        <p key={d.clave} className="t-caption flex justify-between gap-3 pl-3">
                          <span>{d.nombre}</span>
                          <span className="tabular-nums">{montoVisible(d, s.moneda, conIva)}</span>
                        </p>
                      ))}
                    </Renglon>
                  );
                })}
              {[...aparte].map(([clave, filas]) => (
                <Renglon
                  key={clave}
                  titulo={filas[0].nombre}
                  detalle={[`De ${filas.length} ${filas.length === 1 ? "ventana" : "ventanas"}`]}
                  cargado={null}
                  monto={montoVisible(sumarMontos(montos.get(clave) ?? filas), s.moneda, conIva)}
                />
              ))}
            </ul>
          </div>
        );
      })}

      <div className="mt-4 ml-auto w-full max-w-xs border-t border-border-strong pt-3 print:break-inside-avoid">
        <Totales totales={v.totales} importes={v.importes} conIva={conIva} descuento={v.version.descuento} />
      </div>
    </section>
  );
}

function Renglon({
  titulo,
  detalle,
  cargado,
  monto,
  children,
}: {
  titulo: string;
  detalle: (string | null | undefined)[];
  cargado: string | null;
  monto: string | null;
  children?: React.ReactNode;
}) {
  const texto = detalle.filter(Boolean).join(" · ");
  return (
    <li className="flex flex-col gap-0.5 border-b border-border py-2 last:border-b-0 print:break-inside-avoid">
      <div className="flex items-start gap-3">
        <div className="min-w-0 flex-1">
          <p className="t-body-m font-medium text-text-primary">{titulo}</p>
          {texto && <p className="t-caption">{texto}</p>}
          {cargado && <p className="t-caption">{cargado}</p>}
        </div>
        <p className="t-body-m shrink-0 text-right tabular-nums text-text-primary">{monto ?? "—"}</p>
      </div>
      {children}
    </li>
  );
}
