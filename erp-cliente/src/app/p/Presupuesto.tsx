"use client";

import Image from "next/image";
import { useEffect, useMemo, useState } from "react";
import { descifrar, huellaDe } from "@/lib/cifrado";
import { codigoEleccion } from "@/lib/eleccion";
import type { Combinacion, Copia, Moneda, Renglon, Version } from "@/lib/tipos";
import { totalesDe } from "@/lib/totales";

type Carga = { estado: "cargando" } | { estado: "no" } | { estado: "error" } | { estado: "listo"; copia: Copia; monedas: Moneda[] };

const ERP_URL = process.env.NEXT_PUBLIC_ERP_URL ?? "";
const SIMBOLO: Record<string, string> = { ARS: "$", USD_OFICIAL: "US$", USD_BLUE: "US$ blue", EUR: "€" };
const dinero = (monto: number, moneda: string) =>
  `${SIMBOLO[moneda] ?? moneda} ${new Intl.NumberFormat("es-AR", { maximumFractionDigits: moneda === "ARS" ? 0 : 2, minimumFractionDigits: moneda === "ARS" ? 0 : 2 }).format(monto)}`;
const fecha = (iso: string) => new Date(iso.length === 10 ? `${iso}T12:00:00` : iso).toLocaleDateString("es-AR", { day: "numeric", month: "long", year: "numeric" });
const etiqueta = (r: Renglon) => [r.designacion, r.ubicacion].filter(Boolean).join(" · ") || r.nombre || "Ítem";
const mismas = (a: string[], b: string[]) => a.length === b.length && a.every((x) => b.includes(x));

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
      <Image src="/logo.svg" alt="JADA" width={109} height={40} priority />
      {carga.estado === "cargando" && <p className="t-body-m">Cargando…</p>}
      {carga.estado === "error" && <p className="alert alert-error">No pudimos abrir el presupuesto. Probá de nuevo en unos minutos.</p>}
      {carga.estado === "no" && <p className="alert alert-warning">Este presupuesto ya no está disponible.</p>}
      {carga.estado === "listo" && <Cuerpo copia={carga.copia} monedas={carga.monedas} link={link} previa={previa} />}
    </main>
  );
}

function Cuerpo({ copia, monedas, link, previa }: { copia: Copia; monedas: Moneda[]; link: string; previa: boolean }) {
  const [variante, setVariante] = useState(copia.versiones[0]?.variante ?? "");
  const version = copia.versiones.find((v) => v.variante === variante) ?? copia.versiones[0];

  useEffect(() => {
    if (previa || !version) return;
    const d = dispositivo();
    if (!d) return;
    huellaDe(link).then((huella) =>
      fetch("/api/visita", { method: "POST", keepalive: true, headers: { "Content-Type": "application/json" }, body: JSON.stringify({ huella, version: version.numero, dispositivo: d }) }).catch(() => {}),
    );
  }, [link, previa, version]);

  if (!version) return <p className="alert alert-warning">Este presupuesto ya no está disponible.</p>;
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
        <div className="flex flex-wrap gap-2" role="group" aria-label="Variantes">
          {copia.versiones.map((v) => (
            <button key={v.variante} type="button" aria-pressed={v.variante === version.variante} onClick={() => setVariante(v.variante)}
              className={`btn btn-sm min-h-11 ${v.variante === version.variante ? "btn-primary" : "btn-secondary"}`}>
              {v.variante_nombre ?? `Variante ${v.variante}`}
            </button>
          ))}
        </div>
      )}
      <Variante key={version.numero} copia={copia} version={version} monedas={monedas} aprobado={aprobado} />
    </>
  );
}

function Variante({ copia, version, monedas, aprobado }: { copia: Copia; version: Version; monedas: Moneda[]; aprobado: boolean }) {
  const inicial = useMemo(() => Object.fromEntries(version.renglones.map((r) => [r.id, r.combinaciones[0]?.casillas ?? []])), [version]);
  const [tildadas, setTildadas] = useState<Record<string, string[]>>(inicial);
  const [copiado, setCopiado] = useState(false);

  const elegidas = useMemo(() => {
    const e: Record<string, Combinacion> = {};
    for (const r of version.renglones) {
      const c = r.combinaciones.find((x) => mismas(x.casillas, tildadas[r.id] ?? []));
      if (c) e[r.id] = c;
    }
    return e;
  }, [version, tildadas]);
  const totales = useMemo(() => totalesDe(version, elegidas), [version, elegidas]);
  const vencida = version.vence !== null && version.vence < new Date().toISOString().slice(0, 10);
  const cambio = version.renglones.some((r) => r.ancho > 0 && elegidas[r.id]?.n !== 0);

  function alternar(r: Renglon, clave: string) {
    const actual = tildadas[r.id] ?? [];
    const nuevas = actual.includes(clave) ? actual.filter((c) => c !== clave) : [...actual, clave];
    if (r.combinaciones.some((c) => mismas(c.casillas, nuevas))) setTildadas({ ...tildadas, [r.id]: nuevas });
  }

  const mensaje = () => {
    const codigo = codigoEleccion(copia.codigo, version.numero, version.renglones.filter((r) => r.ancho > 0).map((r) => ({ ancho: r.ancho, n: elegidas[r.id]?.n ?? 0 })));
    const lineas = version.renglones.filter((r) => r.casillas.length > 0).map((r) => {
      const nombres = r.casillas.filter((c) => (tildadas[r.id] ?? []).includes(c.clave)).map((c) => c.nombre);
      return `${etiqueta(r)}: ${nombres.length ? nombres.join(", ") : "sin opcionales"}`;
    });
    const total = totales.map((t) => dinero(t.total, t.moneda)).join(" + ");
    return [`Mi elección — ${copia.nombre}${version.variante_nombre ? ` (${version.variante_nombre})` : ""}`, ...lineas, `Total ${total}`, "", `${ERP_URL}/presupuestos/eleccion/${codigo}`].join("\n");
  };
  const whatsapp = copia.whatsapp?.replace(/\D/g, "");

  return (
    <>
      {vencida && version.vence && <p className="alert alert-warning">Venció el {fecha(version.vence)}: los precios pueden cambiar.</p>}
      <ul className="flex flex-col gap-3">
        {version.renglones.map((r) => (
          <li key={r.id} className="card">
            <div className="flex items-start justify-between gap-3">
              <div className="min-w-0">
                <h2 className="t-h3">{etiqueta(r)}</h2>
                {r.nombre && (r.designacion || r.ubicacion) && <p className="t-caption">{r.nombre}</p>}
              </div>
              <p className="t-h3 shrink-0">{elegidas[r.id]?.importe != null ? dinero(elegidas[r.id].importe!, version.secciones.find((s) => s.id === r.seccion_id)?.moneda ?? "ARS") : "Consultar"}</p>
            </div>
            {r.casillas.length > 0 && (
              <fieldset className="mt-3 flex flex-col gap-1" disabled={aprobado}>
                <legend className="t-label mb-1">Opcionales</legend>
                {r.casillas.map((c) => {
                  const marcada = (tildadas[r.id] ?? []).includes(c.clave);
                  const nuevas = marcada ? (tildadas[r.id] ?? []).filter((x) => x !== c.clave) : [...(tildadas[r.id] ?? []), c.clave];
                  const posible = r.combinaciones.some((x) => mismas(x.casillas, nuevas));
                  return (
                    <label key={c.clave} className={`flex min-h-11 items-center gap-3 text-body-m ${posible ? "" : "opacity-50"}`}>
                      <input type="checkbox" className="size-5" checked={marcada} disabled={!posible} onChange={() => alternar(r, c.clave)} />
                      {c.nombre}
                    </label>
                  );
                })}
              </fieldset>
            )}
            {(elegidas[r.id]?.aparte ?? []).map((a) => (
              <p key={a.clave} className="t-caption mt-2">{a.nombre}: {a.importe != null ? dinero(a.importe, version.secciones.find((s) => s.id === a.seccion_id)?.moneda ?? "ARS") : "Consultar"}</p>
            ))}
          </li>
        ))}
      </ul>
      <section className="card">
        <h2 className="t-label mb-2">Total</h2>
        {totales.map((t) => (
          <div key={t.moneda} className="mb-2">
            <p className="t-h2">{dinero(t.total, t.moneda)}</p>
            <p className="t-caption">
              {t.descuento > 0 && <>Descuento {dinero(t.descuento, t.moneda)} · </>}
              IVA {dinero(t.iva, t.moneda)}{t.sinPrecio > 0 && <> · {t.sinPrecio} ítem(s) sin precio</>}
            </p>
            {monedas.filter((m) => m.referencia && m.moneda !== t.moneda).map((m) => {
              const de = monedas.find((x) => x.moneda === t.moneda);
              return de ? <p key={m.moneda} className="t-caption">≈ {dinero((t.total * de.valor) / m.valor, m.moneda)} (referencia)</p> : null;
            })}
          </div>
        ))}
      </section>
      {!aprobado && (
        <div className="flex flex-wrap gap-3">
          {whatsapp && (
            <a className={`btn btn-primary btn-lg min-h-11 ${vencida || !ERP_URL ? "pointer-events-none opacity-50" : ""}`} href={`https://wa.me/${whatsapp}?text=${encodeURIComponent(vencida || !ERP_URL ? "" : mensaje())}`} target="_blank" rel="noreferrer" style={{ color: "white" }}>
              Enviar mi elección por WhatsApp
            </a>
          )}
          <button type="button" className="btn btn-secondary btn-lg min-h-11" disabled={vencida || !ERP_URL}
            onClick={() => navigator.clipboard.writeText(mensaje()).then(() => { setCopiado(true); setTimeout(() => setCopiado(false), 2500); }).catch(() => {})}>
            {copiado ? "Copiado" : "Copiar mi elección"}
          </button>
          {!cambio && <p className="t-caption w-full">Tildá los opcionales que quieras y enviá tu elección.</p>}
        </div>
      )}
    </>
  );
}
