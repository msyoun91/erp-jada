"use client";

import { useState } from "react";

function calcularFecha(dias: number): string {
  const d = new Date();
  d.setDate(d.getDate() + dias);
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
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

  async function confirmar(f: string) {
    setEnviando(true);
    await onConfirm(f);
    setEnviando(false);
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-[rgba(7,11,20,.55)] p-4">
      <div className="w-full max-w-[400px] rounded-xl bg-bg-surface p-[30px] shadow-lg">
        <h2 className="t-h3 mb-4">{title}</h2>

        <div className="flex flex-wrap gap-2">
          <button type="button" className="btn btn-secondary btn-sm" disabled={enviando} onClick={() => confirmar(calcularFecha(1))}>
            1 día
          </button>
          <button type="button" className="btn btn-secondary btn-sm" disabled={enviando} onClick={() => confirmar(calcularFecha(3))}>
            3 días
          </button>
          <button type="button" className="btn btn-secondary btn-sm" disabled={enviando} onClick={() => confirmar(calcularFecha(7))}>
            7 días
          </button>
        </div>

        <div className="mt-4">
          <label className="t-label mb-1 block">O elegí una fecha</label>
          <div className="flex gap-2">
            <input type="date" className="input" value={fecha} onChange={(e) => setFecha(e.target.value)} />
            <button
              type="button"
              className="btn btn-primary btn-sm"
              disabled={!fecha || enviando}
              onClick={() => confirmar(fecha)}
            >
              Posponer
            </button>
          </div>
        </div>

        <div className="mt-5 flex justify-end">
          <button type="button" className="btn btn-secondary" onClick={onClose} disabled={enviando}>
            Cancelar
          </button>
        </div>
      </div>
    </div>
  );
}
