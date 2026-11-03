"use client";

import { ConfirmModal } from "@/components/ui/Modal";
import { lineasBaja } from "../etiquetas";
import type { AvisoBaja } from "../types";

// Antes de confirmar se ve lo que va a pasar: la cuenta la hace la base con las reglas de la baja
// (`catalogo_baja_aviso`). Sin la vista Paquetes llegan solo los números.
export function BajaModal({
  titulo,
  aviso,
  onConfirm,
  onClose,
}: {
  titulo: string;
  aviso: AvisoBaja;
  onConfirm: () => Promise<void>;
  onClose: () => void;
}) {
  const lineas = lineasBaja(aviso);

  return (
    <ConfirmModal
      title={titulo}
      mensaje={
        lineas.length === 0
          ? "No saca nada de la venta: ningún paquete publicado lo necesita."
          : "Los paquetes que salen de la venta no vuelven solos al reactivarlo: los reactiva Técnica. A quienes aprueban les llega un aviso."
      }
      confirmLabel="Dar de baja"
      onConfirm={onConfirm}
      onClose={onClose}
    >
      {lineas.length > 0 && (
        <ul className="flex flex-col gap-1">
          {lineas.map((l) => (
            <li key={l} className="t-body-m text-warning-text">
              {l}
            </li>
          ))}
        </ul>
      )}
    </ConfirmModal>
  );
}
