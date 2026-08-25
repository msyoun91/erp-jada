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
  hayCambios,
  children,
}: {
  title: string;
  onClose: () => void;
  maxWidth?: number;
  // Con cambios sin guardar, cerrar por backdrop/Escape/X pregunta antes:
  // un click al costado no puede borrar lo que el usuario escribió.
  hayCambios?: boolean;
  children: React.ReactNode;
}) {
  const ref = useRef<HTMLDialogElement>(null);
  const [confirmandoCierre, setConfirmandoCierre] = useState(false);

  function intentarCerrar() {
    if (hayCambios) setConfirmandoCierre(true);
    else onClose();
  }

  useEffect(() => {
    ref.current?.showModal();
  }, []);

  return (
    <dialog
      ref={ref}
      onCancel={(e) => {
        e.preventDefault();
        intentarCerrar();
      }}
      onClick={(e) => {
        if (e.target === e.currentTarget) intentarCerrar();
      }}
      className="fixed inset-0 m-0 h-full max-h-none w-full max-w-none items-center justify-center overflow-hidden border-0 bg-transparent p-4 backdrop:bg-[rgba(7,11,20,.55)] open:flex"
    >
      <div
        style={{ maxWidth }}
        className="max-h-full w-full overflow-y-auto rounded-xl bg-bg-surface p-[30px] shadow-lg"
      >
        <div className="mb-5 flex items-center justify-between">
          <h2 className="t-h3">{title}</h2>
          <button onClick={intentarCerrar} className="icon-btn text-text-tertiary" aria-label="Cerrar">
            <X size={20} />
          </button>
        </div>

        {children}
      </div>

      {confirmandoCierre && (
        <DescartarCambios onDescartar={onClose} onSeguir={() => setConfirmandoCierre(false)} />
      )}
    </dialog>
  );
}

export function ConfirmModal({
  title,
  mensaje,
  confirmLabel = "Desactivar",
  cancelLabel = "Cancelar",
  onConfirm,
  onClose,
}: {
  title: string;
  mensaje: string;
  confirmLabel?: string;
  // "Cancelar" no sirve como salida cuando la acción confirmada también se
  // llama cancelar (cancelar una tarea): ahí el que vuelve dice otra cosa.
  cancelLabel?: string;
  onConfirm: () => void | Promise<void>;
  onClose: () => void;
}) {
  const [enviando, setEnviando] = useState(false);

  return (
    <Modal title={title} onClose={onClose}>
      <p className="t-body-m mb-6">{mensaje}</p>
      <div className="flex justify-end gap-2">
        <button className="btn btn-secondary" onClick={onClose} disabled={enviando}>
          {cancelLabel}
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

// Vive acá y no en archivo propio: es ConfirmModal con un copy fijo, y ponerlo
// afuera crearía un ciclo de imports con Modal, que es quien lo usa.
export function DescartarCambios({
  onDescartar,
  onSeguir,
}: {
  onDescartar: () => void;
  onSeguir: () => void;
}) {
  return (
    <ConfirmModal
      title="Descartar cambios"
      mensaje="Hay cambios sin guardar. Si cerrás, se pierden."
      confirmLabel="Descartar"
      cancelLabel="Seguir editando"
      onConfirm={onDescartar}
      onClose={onSeguir}
    />
  );
}
