"use client";

import { useState } from "react";
import { Ban, Eye, Link2, RefreshCw } from "lucide-react";
import { toast } from "sonner";
import { ConfirmModal } from "@/components/ui/Modal";
import { OverflowMenu } from "@/components/ui/OverflowMenu";
import { hace } from "@/lib/utils";
import { anularLink, linkDelPortal, reintentarPortal } from "../actions";
import type { PortalFicha as Portal } from "../queries";
import { PegarEleccion } from "./EleccionView";

function estadoCopia(p: Portal): { texto: string; alDia: boolean } {
  if (p.copia_revision === p.revision) return { texto: "al día", alDia: true };
  if (p.copia_revision === null) return { texto: "todavía no se copió", alDia: false };
  const v = p.copia_versiones ?? [];
  return { texto: v.length ? `sin actualizar, muestra la v${v.join(", v")}` : "sin actualizar", alDia: false };
}

function textoVisitas(p: Portal) {
  if (p.visitas.length === 0) return p.link_copiado_en ? "Todavía nadie lo abrió" : "Todavía no se copió el link";
  return null;
}

export function PortalFicha({ id, portal, arma, publicado }: { id: string; portal: Portal; arma: boolean; publicado: boolean }) {
  const [enviando, setEnviando] = useState(false);
  const [anular, setAnular] = useState(false);
  const copia = estadoCopia(portal);
  const sinVisitas = textoVisitas(portal);

  async function copiar() {
    setEnviando(true);
    const r = await linkDelPortal(id, true);
    setEnviando(false);
    if (!r.success) {
      toast.error(r.error);
      return;
    }
    try {
      await navigator.clipboard.writeText(r.url);
      toast.success("Link copiado");
    } catch {
      toast.error("No se pudo copiar al portapapeles");
    }
  }

  // La pestaña se abre en el click: abierta después del await, el navegador la bloquea.
  async function verComoCliente() {
    const pestana = window.open("", "_blank");
    const r = await linkDelPortal(id, false);
    if (!r.success) {
      pestana?.close();
      toast.error(r.error);
      return;
    }
    if (!pestana) {
      toast.error("El navegador bloqueó la pestaña nueva");
      return;
    }
    pestana.opener = null;
    pestana.location.href = `${r.url}?previa`;
  }

  async function reintentar() {
    setEnviando(true);
    const r = await reintentarPortal(id);
    setEnviando(false);
    if (r.success) toast.success("Portal al día");
    else toast.error(r.error);
  }

  return (
    <div className="card">
      <div className="flex flex-wrap items-center gap-2">
        <h3 className="t-h3 min-w-0 flex-1">Portal del cliente</h3>
        {arma && publicado && <PegarEleccion presupuestoId={id} />}
        {arma && (
          <>
            <button type="button" className="btn btn-secondary btn-sm" disabled={enviando} onClick={copiar}>
              <Link2 size={14} />
              Copiar link
            </button>
            <OverflowMenu
              items={[
                { label: "Ver como cliente", icon: <Eye size={14} />, onClick: verComoCliente },
                ...(copia.alDia ? [] : [{ label: "Reintentar la copia", icon: <RefreshCw size={14} />, onClick: reintentar }]),
                { label: "Anular el link…", icon: <Ban size={14} />, onClick: () => setAnular(true), destructive: true },
              ]}
            />
          </>
        )}
      </div>
      <p className="t-caption mt-1">Portal: {copia.texto}</p>
      {sinVisitas ? (
        <p className="t-body-m mt-2">{sinVisitas}</p>
      ) : (
        <div className="mt-2 flex flex-col">
          {portal.visitas.map((v) => (
            <p key={v.numero} className="t-body-m border-b border-border py-1 last:border-b-0">
              Versión {v.numero}: {v.visitas} {v.visitas === 1 ? "visita" : "visitas"}, {v.dispositivos}{" "}
              {v.dispositivos === 1 ? "dispositivo" : "dispositivos"}
              <span className="t-caption"> · última {hace(v.ultima)}</span>
            </p>
          ))}
        </div>
      )}
      {anular && (
        <ConfirmModal
          title="Anular el link"
          mensaje="El link actual deja de abrir y se crea otro. Lo que ya mandaste al cliente no vuelve a funcionar."
          confirmLabel="Anular"
          onConfirm={async () => {
            const r = await anularLink(id);
            if (r.success) toast.success("Link anulado");
            else toast.error(r.error);
          }}
          onClose={() => setAnular(false)}
        />
      )}
    </div>
  );
}
