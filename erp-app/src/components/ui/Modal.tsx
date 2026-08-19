"use client";

import { useEffect, useRef, useState } from "react";
import { X } from "lucide-react";

// Mismo criterio que RightPanel: <dialog> + showModal() para que el modal
// viva en el top layer del browser. Como div `fixed z-50` quedaba por debajo
// de un panel abierto (top layer) — un modal lanzado desde TareaDetailPanel dentro de
// HiloDetailPanel aparecía tapado por el panel.
export function Modal({
  title,
  onClose,
  maxWidth = 420,
  children,
}: {
  title: string;
  onClose: () => void;
  maxWidth?: number;
  children: React.ReactNode;
}) {
  const ref = useRef<HTMLDialogElement>(null);

  useEffect(() => {
    ref.current?.showModal();
  }, []);

  return (
    <dialog
      ref={ref}
      onCancel={(e) => {
        e.preventDefault();
        onClose();
      }}
      onClick={(e) => {
        if (e.target === e.currentTarget) onClose();
      }}
      className="fixed inset-0 m-0 h-full max-h-none w-full max-w-none items-center justify-center overflow-hidden border-0 bg-transparent p-4 backdrop:bg-[rgba(7,11,20,.55)] open:flex"
    >
      <div
        style={{ maxWidth }}
        className="max-h-full w-full overflow-y-auto rounded-xl bg-bg-surface p-[30px] shadow-lg"
      >
        <div className="mb-5 flex items-center justify-between">
          <h2 className="t-h3">{title}</h2>
          <button onClick={onClose} className="text-text-tertiary" aria-label="Cerrar">
            <X size={20} />
          </button>
        </div>

        {children}
      </div>
    </dialog>
  );
}

export function ConfirmModal({
  title,
  mensaje,
  confirmLabel = "Desactivar",
  onConfirm,
  onClose,
}: {
  title: string;
  mensaje: string;
  confirmLabel?: string;
  onConfirm: () => void | Promise<void>;
  onClose: () => void;
}) {
  const [enviando, setEnviando] = useState(false);

  return (
    <Modal title={title} onClose={onClose}>
      <p className="t-body-m mb-6">{mensaje}</p>
      <div className="flex justify-end gap-2">
        <button className="btn btn-secondary" onClick={onClose} disabled={enviando}>
          Cancelar
        </button>
        <button
          className="btn btn-danger"
          disabled={enviando}
          onClick={async () => {
            setEnviando(true);
            try {
              await onConfirm();
              onClose();
            } finally {
              setEnviando(false);
            }
          }}
        >
          {confirmLabel}
        </button>
      </div>
    </Modal>
  );
}
