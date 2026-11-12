"use client";

import Image from "next/image";
import { useEffect, useMemo, useState } from "react";
import { descifrar, huellaDe } from "@/lib/cifrado";
import { ordenPorNombre, textoCargado } from "@/lib/cargado";
import { cercana, codigoEleccion } from "@/lib/eleccion";
import type { Combinacion, Copia, Moneda, Renglon, Version } from "@/lib/tipos";
import { totalesDe, type Total } from "@/lib/totales";

type Carga = { estado: "cargando" } | { estado: "no" } | { estado: "error" } | { estado: "listo"; copia: Copia; monedas: Moneda[] };

const ERP_URL = process.env.NEXT_PUBLIC_ERP_URL ?? "";
const SIMBOLO: Record<string, string> = { ARS: "$", USD_OFICIAL: "US$", USD_BLUE: "US$ blue", EUR: "€" };
const dinero = (monto: number, moneda: string) =>
  `${SIMBOLO[moneda] ?? moneda} ${new Intl.NumberFormat("es-AR", { maximumFractionDigits: moneda === "ARS" ? 0 : 2, minimumFractionDigits: moneda === "ARS" ? 0 : 2 }).format(monto)}`;
const ZONA = "America/Argentina/Buenos_Aires";
const NOMBRE: Record<string, string> = { ARS: "pesos", USD_OFICIAL: "dólares", USD_BLUE: "dólares blue", EUR: "euros" };
// Como formatFecha del ERP: 30/11/26, en hora argentina.
const fecha = (iso: string) =>
  new Date(iso.length === 10 ? `${iso}T12:00:00Z` : iso).toLocaleDateString("es-AR", { timeZone: ZONA, day: "numeric", month: "numeric", year: "2-digit" });
const hoy = () => new Date().toLocaleDateString("en-CA", { timeZone: ZONA });

// La referencia convierte el total entero, todas las monedas juntas (*Moneda e IVA*). No hace falta si ya está todo en esa moneda.
function referencias(totales: Total[], monedas: Moneda[]) {
  const valor = new Map(monedas.map((m) => [m.moneda, m]));
  return monedas
    .filter((m) => m.referencia && !(totales.length === 1 && totales[0].moneda === m.moneda))
    .flatMap((m) => {
      const de = totales.map((t) => valor.get(t.moneda));
      if (totales.length === 0 || de.some((x) => !x)) return [];
      const monto = totales.reduce((s, t, i) => s + (t.total * de[i]!.valor) / m.valor, 0);
      const fechas = [m, ...de].filter((x) => x && x.moneda !== "ARS").map((x) => x!.fecha).sort();
      return [{ moneda: m.moneda, monto, fecha: fechas.at(-1) ?? null }];
    });
}

// El portal no distingue un link anulado de uno cuya copia todavía no llegó (no confirma qué huellas existen): el texto sirve a los dos.
function NoEncontrado() {
  return (
    <p className="alert alert-warning">
      No encontramos este presupuesto. Si te lo acaban de mandar, probá en unos minutos; si no, pedile el link actualizado a quien te
      lo mandó.
    </p>
  );
}

function Linea({ texto, valor, fuerte }: { texto: string; valor: string; fuerte?: boolean }) {
  return (
    <p className={`flex justify-between gap-3 ${fuerte ? "t-body-l font-semibold text-text-primary" : "t-body-m"}`}>
      <span>{texto}</span>
      <span className="tabular-nums">{valor}</span>
    </p>
  );
}
const etiqueta = (r: Renglon) => r.designacion ?? r.ubicacion ?? r.nombre ?? "Ítem";
const alicuota = (a: number) => `${a.toLocaleString("es-AR")} %`;
// Como el impreso: el paquete si el título es la designación, la ubicación y la cantidad si no es 1.
const detalle = (r: Renglon) =>
  [r.designacion ? r.nombre : null, r.ubicacion, r.cantidad !== 1 ? `${r.cantidad.toLocaleString("es-AR")} u.` : null].filter(Boolean).join(" · ");
const mismas =(a: string[], b: string[]) => a.length === b.length && a.every((x) => b.includes(x));
// Con IVA incluido, cada importe va con IVA, como en el impreso (montoVisible): si no, las ventanas no suman el total.
const visible = (m: { importe: number | null; importe_con_iva: number | null }, v: Version) => (v.iva_discriminado ? m.importe : m.importe_con_iva);

function dispositivo(): string | null {
  try {
    let d = localStorage.getItem("jada-dispositivo");
    if (!d) {
      d = crypto.randomUUID();
      localStorage.setItem("jada-dispositivo", d);
    }
    return d;
  } catch {
    return null;
  }
}

export function Presupuesto() {
  const [carga, setCarga] = useState<Carga>({ estado: "cargando" });
  const [link, setLink] = useState("");
  const [previa, setPrevia] = useState(false);

  useEffect(() => {
    const [l, marca] = window.location.hash.slice(1).split("?");
    const llave = l.toLowerCase();
    (async () => {
      if (!/^[0-9a-f]{32}$/.test(llave)) return setCarga({ estado: "no" });
      setLink(llave);
      setPrevia(marca === "previa");
      try {
        const huella = await huellaDe(llave);
        const r = await fetch("/api/copia", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ huella }) });
        if (!r.ok) return setCarga({ estado: "error" });
        const { copia, monedas } = (await r.json()) as { copia: string | null; monedas: Moneda[] };
        if (!copia) return setCarga({ estado: "no" });
        const c = JSON.parse(await descifrar(llave, copia)) as Copia;
        setCarga({ estado: "listo", copia: c, monedas });
      } catch {
        setCarga({ estado: "error" });
      }
    })();
  }, []);

  return (
    <main className="mx-auto flex w-full max-w-3xl flex-1 flex-col gap-4 px-4 py-6">
      <Image src="/logo.svg" alt="JADA" width={109} height={40} priority className="logo" />
      {carga.estado === "cargando" && <p className="t-body-m">Cargando…</p>}
      {carga.estado === "error" && (
        <div className="flex flex-col items-start gap-3">
          <p className="alert alert-error">No pudimos abrir el presupuesto. Revisá la conexión y probá de nuevo.</p>
          <button type="button" className="btn btn-secondary min-h-11" onClick={() => window.location.reload()}>
            Probar de nuevo
          </button>
        </div>
      )}
      {carga.estado === "no" && <NoEncontrado />}
      {carga.estado === "listo" && <Cuerpo copia={carga.copia} monedas={carga.monedas} link={link} previa={previa} />}
    </main>
  );
}

function Cuerpo({ copia, monedas, link, previa }: { copia: Copia; monedas: Moneda[]; link: string; previa: boolean }) {
  const [variante, setVariante] = useState(copia.versiones[0]?.variante ?? "");
  const version = copia.versiones.find((v) => v.variante === variante) ?? copia.versiones[0];
  // Por versión, para que ir a otra variante y volver no borre lo tildado.
  const [tildadas, setTildadas] = useState<Record<number, Tildadas>>(() =>
    Object.fromEntries(copia.versiones.map((v) => [v.numero, inicialDe(v)])),
  );

  useEffect(() => {
    if (previa || !version) return;
    const d = dispositivo();
    if (!d) return;
    huellaDe(link).then((huella) =>
      fetch("/api/visita", { method: "POST", keepalive: true, headers: { "Content-Type": "application/json" }, body: JSON.stringify({ huella, version: version.numero, dispositivo: d }) }).catch(() => {}),
    );
  }, [link, previa, version]);

  if (!version) return <NoEncontrado />;
  const aprobado = copia.estado === "aprobado";

  return (
    <>
      {previa && <p className="alert alert-warning">Vista previa — no cuenta como visita.</p>}
      <header>
        <p className="t-label">{copia.codigo}</p>
        <h1 className="t-h1">{copia.nombre}</h1>
        {aprobado && copia.aprobado_en && <p className="badge badge-success mt-2 inline-block">Aprobado el {fecha(copia.aprobado_en)}</p>}
      </header>
      {copia.versiones.length > 1 && (
        <div className="segmented w-full max-w-full flex-wrap" role="group" aria-label="Variantes">
          {copia.versiones.map((v) => (
            <button key={v.variante} type="button" aria-pressed={v.variante === version.variante} onClick={() => setVariante(v.variante)}
              className="segmented-item min-h-11 flex-1 flex-col items-start gap-0.5 py-1.5">
              <span className="text-body-m">{v.variante_nombre ?? `Variante ${v.variante}`}</span>
              <span className="tabular-nums">
                {totalesDe(v, elegidasDe(v, tildadas[v.numero] ?? {})).map((t) => dinero(t.total, t.moneda)).join(" + ")}
              </span>
            </button>
          ))}
        </div>
      )}
      <Variante key={version.numero} copia={copia} version={version} monedas={monedas} aprobado={aprobado}
        tildadas={tildadas[version.numero] ?? {}} setTildadas={(t) => setTildadas({ ...tildadas, [version.numero]: t })} />
    </>
  );
}

type Tildadas = Record<string, string[]>;

// La primera combinación de cada ventana es la publicada (presupuestos_portal_version).
const inicialDe = (v: Version): Tildadas => Object.fromEntries(v.renglones.map((r) => [r.id, r.combinaciones[0]?.casillas ?? []]));

function elegidasDe(v: Version, tildadas: Tildadas): Record<string, Combinacion> {
  const e: Record<string, Combinacion> = {};
  for (const r of v.renglones) {
    const c = r.combinaciones.find((x) => mismas(x.casillas, tildadas[r.id] ?? []));
    if (c) e[r.id] = c;
  }
  return e;
}

function Variante({ copia, version, monedas, aprobado, tildadas, setTildadas }: {
  copia: Copia; version: Version; monedas: Moneda[]; aprobado: boolean; tildadas: Tildadas; setTildadas: (t: Tildadas) => void;
}) {
  const [copiado, setCopiado] = useState(false);
  const [fallaCopia, setFallaCopia] = useState(false);
  const [avisos, setAvisos] = useState<Record<string, string | null>>({});

  const elegidas = useMemo(() => elegidasDe(version, tildadas), [version, tildadas]);
  const totales = useMemo(() => totalesDe(version, elegidas), [version, elegidas]);
  const orden = useMemo(() => ordenPorNombre(version.orden ?? {}), [version]);
  const vencida = version.vence !== null && version.vence < hoy();

  function alternar(r: Renglon, clave: string) {
    const actual = tildadas[r.id] ?? [];
    const c = cercana(r, actual, clave);
    if (!c) return;
    setTildadas({ ...tildadas, [r.id]: c.casillas });
    // Lo que cambió además de lo tocado, como el ERP con la Cortina y el Cajón: se dice, no se hace en silencio.
    const nombre = (k: string) => r.casillas.find((x) => x.clave === k)?.nombre ?? k;
    const tocada = nombre(clave);
    const suma = c.casillas.filter((k) => k !== clave && !actual.includes(k)).map(nombre);
    const saca = actual.filter((k) => k !== clave && !c.casillas.includes(k)).map(nombre);
    const aviso = [
      saca.length ? `Sacamos también ${saca.join(", ")}: no se ofrece sin ${tocada}.` : null,
      suma.length ? `Sumamos también ${suma.join(", ")}: ${tocada} no se ofrece sin eso.` : null,
    ].filter(Boolean).join(" ");
    setAvisos({ ...avisos, [r.id]: aviso || null });
  }

  const mensaje = () => {
    const codigo = codigoEleccion(copia.codigo, version.numero, version.renglones.filter((r) => r.ancho > 0).map((r) => ({ ancho: r.ancho, n: elegidas[r.id]?.n ?? 0 })));
    // Por opcional y no por ventana: "Mosquitero: V1, V3, V7". Todas y ninguna cuentan solo donde ese opcional existe.
    const porOpcional = new Map<string, { nombre: string; con: string[]; de: number }>();
    for (const r of version.renglones)
      for (const c of r.casillas) {
        const g = porOpcional.get(c.clave) ?? { nombre: c.nombre, con: [], de: 0 };
        g.de += 1;
        if ((tildadas[r.id] ?? []).includes(c.clave)) g.con.push(etiqueta(r));
        porOpcional.set(c.clave, g);
      }
    const lineas = [...porOpcional.values()].map(
      (g) => `${g.nombre}: ${g.con.length === 0 ? "ninguna" : g.con.length === g.de ? "todas" : g.con.join(", ")}`,
    );
    const total = totales.map((t) => dinero(t.total, t.moneda)).join(" + ");
    return [`Mi elección — ${copia.codigo} · ${copia.nombre}${version.variante_nombre ? ` (${version.variante_nombre})` : ""}`, ...lineas, `Total ${total}`, "", `${ERP_URL}/presupuestos/eleccion/${codigo}`].join("\n");
  };
  const whatsapp = copia.whatsapp?.replace(/\D/g, "");

  return (
    <>
      {version.vence && !aprobado &&
        (vencida ? (
          <p className="alert alert-warning">Venció el {fecha(version.vence)}: los precios pueden cambiar.</p>
        ) : (
          <p className="t-body-m">Válido hasta el {fecha(version.vence)}</p>
        ))}
      {version.secciones.map((s) => {
        const propios = version.renglones.filter((r) => r.seccion_id === s.id);
        // El renglón aparte de cada opcional: la suma de sus líneas en todas las ventanas, con su mínimo si está en esta
        // sección, como el impreso (*Secciones y opcionales*).
        const aparte = new Map<string, { nombre: string; ventanas: number; montos: (number | null)[] }>();
        for (const r of version.renglones)
          for (const a of elegidas[r.id]?.aparte ?? [])
            if (a.seccion_id === s.id) {
              const g = aparte.get(a.clave) ?? { nombre: a.nombre, ventanas: 0, montos: [] };
              g.ventanas += 1;
              g.montos.push(visible(a, version));
              aparte.set(a.clave, g);
            }
        const sumados = new Set<string>();
        for (const r of propios) {
          const g = r.tipo === "minimo" && r.minimo_de ? aparte.get(r.minimo_de) : undefined;
          if (g && elegidas[r.id]) {
            g.montos.push(visible(elegidas[r.id], version));
            sumados.add(r.id);
          }
        }
        const filas = propios.filter((r) => !sumados.has(r.id));
        if (filas.length === 0 && aparte.size === 0) return null;
        const montos = [...filas.map((r) => (elegidas[r.id] ? visible(elegidas[r.id], version) : null)), ...[...aparte.values()].flatMap((g) => g.montos)];
        const subtotal = montos.some((m) => m === null) ? null : montos.reduce<number>((t, m) => t + (m ?? 0), 0);
        return (
          <section key={s.id} aria-label={s.nombre} className="flex flex-col gap-3">
            <div className="flex flex-wrap items-baseline gap-x-3">
              <h2 className="t-h3 min-w-0 flex-1">{s.nombre}</h2>
              <span className="t-caption">{SIMBOLO[s.moneda] ?? s.moneda} · IVA {alicuota(s.alicuota)}</span>
            </div>
            <ul className="flex flex-col gap-3">
              {filas.map((r) => {
                const combinacion = elegidas[r.id];
                const monto = combinacion ? visible(combinacion, version) : null;
                return (
                  <li key={r.id} className="card">
                    <div className="flex items-start justify-between gap-3">
                      <div className="min-w-0">
                        <h3 className="t-h3">{r.tipo === "minimo" ? `Mínimo de ${r.nombre ?? "servicio"}` : (r.designacion ?? r.nombre ?? "Ítem")}</h3>
                        {r.tipo !== "minimo" && detalle(r) && <p className="t-caption">{detalle(r)}</p>}
                        {r.entrada && textoCargado(r.entrada, version.nombres ?? {}, orden) && (
                          <p className="t-caption">{textoCargado(r.entrada, version.nombres ?? {}, orden)}</p>
                        )}
                      </div>
                      <p className="t-h3 shrink-0 tabular-nums">{monto != null ? dinero(monto, s.moneda) : "Consultar"}</p>
                    </div>
                    {r.casillas.length > 0 && (
                      <fieldset className="mt-3 flex flex-col gap-1" disabled={aprobado}>
                        <legend className="t-label mb-1">Opcionales</legend>
                        {r.casillas.map((c) => {
                          const marcada = (tildadas[r.id] ?? []).includes(c.clave);
                          const posible = cercana(r, tildadas[r.id] ?? [], c.clave) !== null;
                          // Debajo de la ventana, la casilla es la línea: tildada, con su monto (*Secciones y opcionales*).
                          const linea = marcada ? combinacion?.debajo.find((d) => d.clave === c.clave) : undefined;
                          const importe = linea ? visible(linea, version) : null;
                          return (
                            <label key={c.clave} className={`flex min-h-11 items-center gap-3 text-body-m ${posible ? "" : "opacity-50"}`}>
                              <input type="checkbox" className="size-5" checked={marcada} disabled={!posible} onChange={() => alternar(r, c.clave)} />
                              <span className="min-w-0 flex-1">
                                {c.nombre}
                                {!posible && <span className="t-caption block">No disponible en esta ventana</span>}
                              </span>
                              {importe != null && <span className="tabular-nums">{dinero(importe, s.moneda)}</span>}
                            </label>
                          );
                        })}
                        <p className="t-caption" aria-live="polite">{avisos[r.id]}</p>
                      </fieldset>
                    )}
                  </li>
                );
              })}
              {[...aparte].map(([clave, g]) => {
                const suma = g.montos.some((m) => m === null) ? null : g.montos.reduce<number>((t, m) => t + (m ?? 0), 0);
                return (
                  <li key={clave} className="card flex items-start justify-between gap-3">
                    <div className="min-w-0">
                      <h3 className="t-h3">{g.nombre}</h3>
                      <p className="t-caption">De {g.ventanas} {g.ventanas === 1 ? "ventana" : "ventanas"}</p>
                    </div>
                    <p className="t-h3 shrink-0 tabular-nums">{suma != null ? dinero(suma, s.moneda) : "Consultar"}</p>
                  </li>
                );
              })}
            </ul>
            {version.secciones.length > 1 && subtotal != null && (
              <p className="t-body-m flex justify-between gap-3 px-1">
                <span>Subtotal {s.nombre}</span>
                <span className="tabular-nums">{dinero(subtotal, s.moneda)}</span>
              </p>
            )}
          </section>
        );
      })}
      <section className="card flex flex-col gap-4" aria-label="Total">
        {totales.map((t) => {
          // Con IVA incluido, el descuento es subtotal − total: absorbe el redondeo, como en el impreso (Totales.tsx).
          const subtotal = version.iva_discriminado ? t.subtotal : t.subtotalConIva;
          const descuento = version.iva_discriminado ? t.descuento : subtotal - t.total;
          return (
            <div key={t.moneda} className="flex flex-col gap-1">
              {totales.length > 1 && <p className="t-label">{SIMBOLO[t.moneda] ?? t.moneda}</p>}
              <Linea texto="Subtotal" valor={dinero(subtotal, t.moneda)} />
              {descuento !== 0 && <Linea texto={`Descuento ${alicuota(version.descuento)}`} valor={`− ${dinero(descuento, t.moneda)}`} />}
              {version.iva_discriminado && t.iva.map((x) => <Linea key={x.alicuota} texto={`IVA ${alicuota(x.alicuota)}`} valor={dinero(x.monto, t.moneda)} />)}
              <Linea texto={version.iva_discriminado ? "Total" : "Total con IVA"} valor={dinero(t.total, t.moneda)} fuerte />
              {t.sinPrecio > 0 && (
                <p className="alert alert-warning mt-1">
                  {t.sinPrecio === 1 ? "1 importe sin precio no suma." : `${t.sinPrecio} importes sin precio no suman.`}
                </p>
              )}
            </div>
          );
        })}
        {referencias(totales, monedas).map((r) => (
          <p key={r.moneda} className="t-caption">
            Todo en {NOMBRE[r.moneda] ?? r.moneda} ≈ {dinero(r.monto, r.moneda)}
            {r.fecha && <> (cambio del {fecha(r.fecha)})</>}
          </p>
        ))}
      </section>
      {!aprobado && vencida && version.vence && (
        // Vencida no se elige (*Qué muestra según el estado*), pero el cliente no queda sin salida: pide precios nuevos.
        whatsapp ? (
          <a className="btn btn-primary btn-lg min-h-11 self-start text-white hover:text-white" target="_blank" rel="noreferrer"
            href={`https://wa.me/${whatsapp}?text=${encodeURIComponent(`Hola, el presupuesto ${copia.codigo} · ${copia.nombre} venció el ${fecha(version.vence)}. ¿Me pasás los precios actualizados?`)}`}>
            Pedir precios actualizados por WhatsApp
          </a>
        ) : (
          <p className="t-body-m">Pedile los precios actualizados a quien te lo mandó.</p>
        )
      )}
      {!aprobado && !vencida && (
        <div className="flex flex-col gap-3">
          <p className="t-body-m">Tildá los opcionales que quieras y enviá tu elección. No confirma la compra: te contactamos para cerrarla.</p>
          <div className="flex flex-wrap gap-3">
            {whatsapp &&
              (ERP_URL ? (
                <a className="btn btn-primary btn-lg min-h-11 text-white hover:text-white" href={`https://wa.me/${whatsapp}?text=${encodeURIComponent(mensaje())}`} target="_blank" rel="noreferrer">
                  Enviar mi elección por WhatsApp
                </a>
              ) : (
                <button type="button" className="btn btn-primary btn-lg min-h-11" disabled>
                  Enviar mi elección por WhatsApp
                </button>
              ))}
            <button type="button" className="btn btn-secondary btn-lg min-h-11" disabled={!ERP_URL}
              onClick={() =>
                navigator.clipboard
                  .writeText(mensaje())
                  .then(() => {
                    setFallaCopia(false);
                    setCopiado(true);
                    setTimeout(() => setCopiado(false), 2500);
                  })
                  .catch(() => setFallaCopia(true))
              }>
              {copiado ? "Copiado" : "Copiar mi elección"}
            </button>
            <span className="sr-only" aria-live="polite">{copiado ? "Elección copiada" : ""}</span>
          </div>
          {fallaCopia && (
            <label className="flex flex-col gap-1">
              <span className="alert alert-warning">No se pudo copiar: seleccioná el texto y copialo de acá.</span>
              <textarea readOnly rows={6} className="input" value={mensaje()} onFocus={(e) => e.currentTarget.select()} />
            </label>
          )}
        </div>
      )}
    </>
  );
}
