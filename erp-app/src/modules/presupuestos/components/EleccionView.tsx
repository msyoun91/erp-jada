"use client";

import { useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { TriangleAlert } from "lucide-react";
import { formatMonto } from "@/lib/monedas";
import { aplicarEleccion } from "../actions";
import type { Eleccion } from "../types";

type Resultado = { eleccion: Eleccion } | { error: string };

function totales(filas: Eleccion["cliente"]) {
  return filas.map((t) => formatMonto(t.total, t.moneda)).join(" + ");
}

// Lo que cambia por ventana: las casillas que se prenden y las que se apagan respecto de la publicada.
function Cambios({ v }: { v: Eleccion["ventanas"][number] }) {
  const nombre = (clave: string) => v.casillas.find((c) => c.clave === clave)?.nombre ?? clave;
  const suma = v.despues.filter((c) => !v.antes.includes(c)).map(nombre);
  const quita = v.antes.filter((c) => !v.despues.includes(c)).map(nombre);
  return (
    <li className="flex flex-col gap-0.5">
      <span className="t-body-m font-semibold">{v.etiqueta}</span>
      {suma.length === 0 && quita.length === 0 ? (
        <span className="t-caption">Sin cambios respecto de la publicada</span>
      ) : (
        <>
          {suma.length > 0 && <span className="t-body-m">Suma: {suma.join(", ")}</span>}
          {quita.length > 0 && <span className="t-body-m">Quita: {quita.join(", ")}</span>}
        </>
      )}
    </li>
  );
}

export function EleccionView({ texto, resultado, desde }: { texto: string; resultado: Resultado; desde: string | null }) {
  const router = useRouter();
  const [enviando, setEnviando] = useState(false);

  if ("error" in resultado) {
    return (
      <div className="card flex flex-col gap-2">
        <h2 className="t-h2">No se puede aplicar la elección</h2>
        <p className="alert alert-error">{resultado.error}</p>
      </div>
    );
  }
  const e = resultado.eleccion;

  async function aplicar() {
    setEnviando(true);
    const r = await aplicarEleccion({ texto });
    if (!r.success) {
      setEnviando(false);
      toast.error(r.error);
      return;
    }
    const a = r.aplicada;
    toast.success(
      `Versión ${a.numero} armada. El cliente vio ${totales(a.cliente)} · con los precios de la ${e.numero}, ${totales(a.publicada)} · a hoy, ${totales(a.hoy)}`
    );
    router.push(`/presupuestos/${e.presupuesto_id}/${r.aplicada.version_id}`);
  }

  return (
    <div className="card flex flex-col gap-4">
      <div>
        <h2 className="t-h2">Elección del cliente · {e.codigo}</h2>
        <p className="t-caption">
          Sobre la versión {e.numero}
          {e.variante_nombre ? ` · ${e.variante_nombre}` : ""}
        </p>
      </div>
      {desde && desde !== e.presupuesto_id && (
        <p className="alert alert-warning flex items-start gap-2">
          <TriangleAlert size={16} className="mt-0.5 shrink-0" />
          Esta elección es del presupuesto {e.codigo}, no del que tenías abierto.
        </p>
      )}
      <ul className="flex flex-col gap-3">
        {e.ventanas.map((v) => (
          <Cambios key={v.renglon_id} v={v} />
        ))}
      </ul>
      <p className="t-body-m">
        El cliente vio <span className="font-semibold">{totales(e.cliente)}</span>.
      </p>
      {e.descarta && (
        <p className="alert alert-warning flex items-start gap-2">
          <TriangleAlert size={16} className="mt-0.5 shrink-0" />
          Se descarta la versión {e.descarta.numero}
          {e.descarta.estado === "en_revision" ? " (en revisión: se retira antes y sus pedidos quedan retirados)" : ""}.
        </p>
      )}
      <p className="t-caption">
        Se arma una versión nueva, desde la {e.numero}, a precios de hoy. Si querés sostener el precio que vio el cliente, usá
        &ldquo;Mantener todas&rdquo; en esa versión: pide la autorización de siempre.
      </p>
      <div className="flex justify-end gap-2">
        <Link href={`/presupuestos/${e.presupuesto_id}`} className="btn btn-secondary btn-sm">
          Cancelar
        </Link>
        <button type="button" className="btn btn-primary btn-sm" disabled={enviando} onClick={aplicar}>
          Aplicar elección
        </button>
      </div>
    </div>
  );
}
