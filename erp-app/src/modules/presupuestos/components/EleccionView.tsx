"use client";

import { useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { ClipboardPaste } from "lucide-react";
import { toast } from "sonner";
import { claseInput } from "@/components/ui/Campo";
import { Modal } from "@/components/ui/Modal";
import { formatMontoCliente } from "@/lib/monedas";
import { aplicarEleccion, leerEleccion } from "../actions";
import type { EleccionAplicada, EleccionLeida, TotalEleccion } from "../types";

function totalesTexto(totales: TotalEleccion[]) {
  if (totales.length === 0) return "sin importes";
  return totales
    .map((t) => formatMontoCliente(t.total, t.moneda) + (t.sin_precio > 0 ? ` (${t.sin_precio} sin precio)` : ""))
    .join(" · ");
}

// Lo que importa después de aplicar: si a hoy cambió respecto de lo que vio el cliente, por moneda.
function Diferencia({ cliente, hoy }: { cliente: TotalEleccion[]; hoy: TotalEleccion[] }) {
  const cambios = hoy.flatMap((h) => {
    const c = cliente.find((x) => x.moneda === h.moneda);
    const dif = h.total - (c?.total ?? 0);
    return dif === 0 ? [] : [{ h, c, dif }];
  });
  if (cambios.length === 0) return <p className="alert alert-success">Mismo total que vio el cliente.</p>;
  return (
    <div className="alert alert-warning flex flex-col gap-1">
      {cambios.map(({ h, c, dif }) => (
        <p key={h.moneda}>
          A hoy da {formatMontoCliente(Math.abs(dif), h.moneda)} {dif > 0 ? "más" : "menos"} que lo que vio el cliente (
          {c ? formatMontoCliente(c.total, h.moneda) : "—"} → {formatMontoCliente(h.total, h.moneda)}).
        </p>
      ))}
      <p>La versión quedó a hoy. Para sostener el precio del cliente, abrila y usá &ldquo;Mantener todas&rdquo;.</p>
    </div>
  );
}

// Lo que cambia en cada ventana: las casillas con nombre, de la clave que guarda la base.
function Ventanas({ eleccion }: { eleccion: EleccionLeida }) {
  const cambian = eleccion.ventanas.filter(
    (v) => v.antes.length !== v.despues.length || v.antes.some((c) => !v.despues.includes(c)),
  );
  if (cambian.length === 0) return <p className="t-body-m">La elección coincide con lo publicado: no cambia ninguna ventana.</p>;
  return (
    <ul className="flex flex-col gap-2">
      {cambian.map((v) => {
        const nombre = (c: string) => v.casillas.find((x) => x.clave === c)?.nombre ?? c;
        const suma = v.despues.filter((c) => !v.antes.includes(c)).map(nombre);
        const saca = v.antes.filter((c) => !v.despues.includes(c)).map(nombre);
        return (
          <li key={v.renglon_id} className="t-body-m">
            <span className="font-semibold">{v.etiqueta}</span>
            {suma.length > 0 && <span> · suma {suma.join(", ")}</span>}
            {saca.length > 0 && <span> · saca {saca.join(", ")}</span>}
          </li>
        );
      })}
    </ul>
  );
}

// Lo que va a pasar antes de aplicar, y los tres totales después. La base valida todo de nuevo al aplicar.
export function EleccionVista({ eleccion, texto }: { eleccion: EleccionLeida; texto: string }) {
  const router = useRouter();
  const [enviando, setEnviando] = useState(false);
  const [aplicada, setAplicada] = useState<EleccionAplicada | null>(null);

  async function aplicar() {
    setEnviando(true);
    const r = await aplicarEleccion({ texto });
    setEnviando(false);
    if (!r.success) {
      toast.error(r.error);
      return;
    }
    setAplicada(r.aplicada);
    router.refresh();
  }

  if (aplicada) {
    return (
      <div className="flex flex-col gap-3">
        <p className="t-body-m">
          Quedó la versión {aplicada.numero} de {eleccion.codigo}
          {aplicada.descartada !== null && `; se descartó la versión ${aplicada.descartada}`}.
        </p>
        <dl className="t-body-m flex flex-col gap-1">
          <div>El cliente vio: <span className="font-semibold">{totalesTexto(aplicada.cliente)}</span></div>
          <div>Con los precios de la publicada: <span className="font-semibold">{totalesTexto(aplicada.publicada)}</span></div>
          <div>A hoy: <span className="font-semibold">{totalesTexto(aplicada.hoy)}</span></div>
        </dl>
        <Diferencia cliente={aplicada.cliente} hoy={aplicada.hoy} />
        <Link href={`/presupuestos/${eleccion.presupuesto_id}/${aplicada.version_id}`} className="btn btn-primary btn-sm self-start">
          Abrir la versión {aplicada.numero}
        </Link>
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-3">
      <p className="t-body-m">
        <span className="font-semibold">{eleccion.codigo}</span> · {eleccion.variante_nombre ?? "Presupuesto"}, versión {eleccion.numero}
      </p>
      <Ventanas eleccion={eleccion} />
      <p className="t-body-m">
        El cliente vio: <span className="font-semibold">{totalesTexto(eleccion.cliente)}</span>
      </p>
      {eleccion.descarta && (
        <p className="alert alert-warning">
          Se descarta la versión {eleccion.descarta.numero}
          {eleccion.descarta.estado === "en_revision" && " (en revisión: se retira antes)"}.
        </p>
      )}
      <p className="t-caption">Se crea una versión nueva desde la {eleccion.numero}, con lo que eligió el cliente. Nada más cambia.</p>
      <button type="button" className="btn btn-primary btn-sm self-start" disabled={enviando} onClick={aplicar}>
        Aplicar elección
      </button>
    </div>
  );
}

export function PegarEleccion({ presupuestoId }: { presupuestoId: string }) {
  const [abierto, setAbierto] = useState(false);
  const [texto, setTexto] = useState("");
  const [leyendo, setLeyendo] = useState(false);
  const [eleccion, setEleccion] = useState<EleccionLeida | null>(null);
  const [error, setError] = useState<string | null>(null);

  function cerrar() {
    setAbierto(false);
    setTexto("");
    setEleccion(null);
    setError(null);
  }

  async function leer() {
    setLeyendo(true);
    setError(null);
    setEleccion(null);
    const r = await leerEleccion({ texto });
    setLeyendo(false);
    if (!r.success) setError(r.error);
    else if (r.eleccion.presupuesto_id !== presupuestoId) {
      setError(`Es una elección de ${r.eleccion.codigo}, no de este presupuesto.`);
    } else setEleccion(r.eleccion);
  }

  return (
    <>
      <button type="button" className="btn btn-secondary btn-sm" onClick={() => setAbierto(true)}>
        <ClipboardPaste size={14} />
        Pegar elección
      </button>
      {abierto && (
        <Modal title="Pegar elección del cliente" onClose={cerrar} maxWidth={520} hayCambios={texto.length > 0 && !eleccion}>
          <div className="flex flex-col gap-3">
            <textarea
              rows={4}
              className={claseInput(undefined)}
              aria-label="Mensaje o link de la elección"
              placeholder="Pegá el mensaje del cliente o el link"
              value={texto}
              onChange={(e) => {
                setTexto(e.target.value);
                setEleccion(null);
                setError(null);
              }}
            />
            {error && <p className="input-error-text">{error}</p>}
            {!eleccion && (
              <button type="button" className="btn btn-secondary btn-sm self-start" disabled={leyendo || !texto.trim()} onClick={leer}>
                Ver qué cambia
              </button>
            )}
            {eleccion && <EleccionVista eleccion={eleccion} texto={texto} />}
          </div>
        </Modal>
      )}
    </>
  );
}
