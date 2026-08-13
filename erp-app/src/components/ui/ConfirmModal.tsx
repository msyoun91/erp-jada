"use client";

export function ConfirmModal({
  title,
  message,
  confirmLabel = "Confirmar",
  danger,
  onConfirm,
  onCancel,
}: {
  title: string;
  message: string;
  confirmLabel?: string;
  danger?: boolean;
  onConfirm: () => void;
  onCancel: () => void;
}) {
  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-[rgba(7,11,20,.55)] p-4">
      <div className="w-full max-w-[400px] rounded-xl bg-bg-surface p-[30px] shadow-lg">
        <h2 className="t-h3 mb-2">{title}</h2>
        <p className="t-body-m mb-5">{message}</p>
        <div className="flex justify-end gap-3">
          <button className="btn btn-secondary" onClick={onCancel}>
            Cancelar
          </button>
          <button className={`btn ${danger ? "btn-danger" : "btn-primary"}`} onClick={onConfirm}>
            {confirmLabel}
          </button>
        </div>
      </div>
    </div>
  );
}
