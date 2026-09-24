"use client";

import { Modal } from "@/components/ui/Modal";

export function FormModal({
  title,
  onClose,
  onSubmit,
  enviando,
  hayCambios,
  confirmLabel,
  peligro,
  children,
}: {
  title: string;
  onClose: () => void;
  onSubmit: React.FormEventHandler<HTMLFormElement>;
  enviando: boolean;
  hayCambios?: boolean;
  confirmLabel: string;
  peligro?: boolean;
  children: React.ReactNode;
}) {
  return (
    <Modal title={title} onClose={onClose} hayCambios={hayCambios}>
      <form onSubmit={onSubmit} className="flex flex-col gap-4">
        {children}
        <div className="flex justify-end gap-2">
          <button type="button" className="btn btn-secondary" onClick={onClose} disabled={enviando}>
            Volver
          </button>
          <button type="submit" className={`btn ${peligro ? "btn-danger" : "btn-primary"}`} disabled={enviando}>
            {enviando ? "Guardando…" : confirmLabel}
          </button>
        </div>
      </form>
    </Modal>
  );
}
