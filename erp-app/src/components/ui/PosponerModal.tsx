"use client";

import { useState } from "react";
import { aISO, desdeISO, hoyISO } from "@/lib/utils";
import { Modal } from "./Modal";

function enDias(dias: number): string {
  const d = desdeISO(hoyISO());
  d.setDate(d.getDate() + dias);
  return aISO(d);
}

export function PosponerModal({
  title = "Posponer",
  onConfirm,
  onClose,
}: {
  title?: string;
  onConfirm: (fecha: string) => void | Promise<void>;
  onClose: () => void;
}) {
  const [fecha, setFecha] = useState("");
  const [enviando, setEnviando] = useState(false);
  const manana = enDias(1);

  async function confirmar(f: string) {
    setEnviando(true);
    await onConfirm(f);
    setEnviando(false);
  }

  return (
    <Modal
      title={title}
      onClose={onClose}
      footer={
        <button type="button" className="btn btn-secondary" onClick={onClose} disabled={enviando}>
          Cancelar
        </button>
      }
    >
      <div className="flex flex-wrap gap-2">
        {[1, 3, 7].map((dias) => (
          <button
            key={dias}
            type="button"
            className="btn btn-secondary btn-sm"
            disabled={enviando}
            onClick={() => confirmar(enDias(dias))}
          >
            {dias} día{dias === 1 ? "" : "s"}
          </button>
        ))}
      </div>

      <div className="mt-4">
        <label className="t-label mb-1 block" htmlFor="posponer-fecha">
          O elegí una fecha
        </label>
        <div className="flex gap-2">
          <input
            id="posponer-fecha"
            type="date"
            className="input"
            min={manana}
            value={fecha}
            onChange={(e) => setFecha(e.target.value)}
          />
          <button
            type="button"
            className="btn btn-primary btn-sm"
            disabled={!fecha || fecha < manana || enviando}
            onClick={() => confirmar(fecha)}
          >
            Posponer
          </button>
        </div>
      </div>
    </Modal>
  );
}
