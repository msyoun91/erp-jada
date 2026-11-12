"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { Copy, Eye, RefreshCw, Unlink } from "lucide-react";
import { ConfirmModal } from "@/components/ui/Modal";
import { formatFechaHora } from "@/lib/utils";
import { anularLinkPortal, llaveDelPortal, reintentarPortal } from "../actions";
import type { EstadoPortal } from "../queries";

function textoCopia(e: EstadoPortal) {
  if (e.copia === "al_dia") return "Al día";
  if (e.copia === "sin_copiar") return "Sin copiar todavía";
  return e.muestra.length > 0 ? `Sin actualizar, muestra la v${e.muestra.join(", v")}` : "Sin actualizar";
}

export function PortalFicha({
  id,
  estado,
  portalUrl,
  arma,
}: {
  id: string;
  estado: EstadoPortal;
  // Sin la dirección del portal no se puede armar el link.
  portalUrl: string | null;
  arma: boolean;
}) {
  const router = useRouter();
  const [enviando, setEnviando] = useState(false);
  const [anular, setAnular] = useState(false);

  async function link(copiar: boolean) {
    if (!portalUrl) return;
    setEnviando(true);
    // La pestaña se abre antes del await: después, el navegador la toma por un pop-up.
    const pestana = copiar ? null : window.open("", "_blank");
    const r = await llaveDelPortal(id, copiar);
    setEnviando(false);
    if (!r.success) {
      pestana?.close();
      toast.error(r.error);
      return;
    }
    const url = `${portalUrl}/p#${r.llave}`;
    if (copiar) {
      try {
        await navigator.clipboard.writeText(url);
        toast.success("Link copiado");
      } catch {
        toast.error("No se pudo copiar. Probá de nuevo.");
      }
      router.refresh();
    } else if (pestana) {
      pestana.location.href = `${url}?previa`;
    }
  }

  async function reintentar() {
    setEnviando(true);
    const r = await reintentarPortal(id);
    setEnviando(false);
    if (r.success) toast.success("Portal actualizado");
    else toast.error(r.error);
    router.refresh();
  }

  return (
    <div className="card flex flex-col gap-2">
      <div className="flex flex-wrap items-center gap-2">
        <h3 className="t-h3 min-w-0 flex-1">Portal del cliente</h3>
        {arma && (
          <>
            {estado.copia !== "al_dia" && (
              <button type="button" className="btn btn-secondary btn-sm" disabled={enviando} onClick={reintentar}>
                <RefreshCw size={14} />
                Reintentar
              </button>
            )}
            <button type="button" className="btn btn-secondary btn-sm" disabled={enviando || !portalUrl} onClick={() => link(false)}>
              <Eye size={14} />
              Ver como cliente
            </button>
            <button type="button" className="btn btn-secondary btn-sm" disabled={enviando} onClick={() => setAnular(true)}>
              <Unlink size={14} />
              Anular link
            </button>
            <button type="button" className="btn btn-primary btn-sm" disabled={enviando || !portalUrl} onClick={() => link(true)}>
              <Copy size={14} />
              Copiar link
            </button>
          </>
        )}
      </div>
      <p className="t-body-m">
        Copia: <span className="font-semibold">{textoCopia(estado)}</span>
      </p>
      {estado.visitas.length > 0 ? (
        <ul className="flex flex-col gap-0.5">
          {estado.visitas.map((v) => (
            <li key={v.numero} className="t-body-m">
              v{v.numero}: {v.visitas} {v.visitas === 1 ? "visita" : "visitas"}, {v.dispositivos}{" "}
              {v.dispositivos === 1 ? "dispositivo" : "dispositivos"} · última {formatFechaHora(v.ultima)}
            </li>
          ))}
        </ul>
      ) : (
        <p className="t-caption">{estado.copiado ? "Sin abrir todavía." : "El link todavía no se copió."}</p>
      )}
      {arma && !portalUrl && <p className="t-caption">Falta cargar PORTAL_URL: sin ella no se arma el link.</p>}
      {anular && (
        <ConfirmModal
          title="Anular el link"
          mensaje="El link actual deja de abrir y se crea otro. El que ya mandaste a un cliente no vuelve a funcionar."
          confirmLabel="Anular"
          onConfirm={async () => {
            const r = await anularLinkPortal(id);
            if (r.success) toast.success("Link anulado");
            else toast.error(r.error);
          }}
          onClose={() => setAnular(false)}
        />
      )}
    </div>
  );
}
