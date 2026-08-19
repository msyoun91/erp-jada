"use client";

import { useEffect, useRef } from "react";
import { X } from "lucide-react";

// <dialog> + showModal(): el panel vive en el top layer del browser, así que
// no lo puede tapar ni recortar ningún ancestro (stacking context, overflow,
// transform) — y con paneles anidados (TareaDetailPanel dentro de HiloDetailPanel)
// el último abierto queda arriba y Escape cierra solo ese, sin manejar
// z-index ni listeners propios.
export function RightPanel({
  title,
  subtitle,
  onClose,
  footer,
  children,
}: {
  title: string;
  subtitle?: string;
  onClose: () => void;
  footer?: React.ReactNode;
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
      className="fixed inset-0 m-0 h-full max-h-none w-full max-w-none justify-end overflow-hidden border-0 bg-transparent p-0 backdrop:bg-[rgba(7,11,20,.55)] open:flex"
    >
      <div className="relative flex h-full w-full max-w-md flex-col border-l border-border bg-bg-surface shadow-lg">
        <div className="flex shrink-0 items-center justify-between border-b border-border px-5 py-4">
          <div>
            <h2 className="t-h3">{title}</h2>
            {subtitle && <p className="t-caption">{subtitle}</p>}
          </div>
          <button onClick={onClose} className="text-text-tertiary" aria-label="Cerrar">
            <X size={18} strokeWidth={1.75} />
          </button>
        </div>

        <div className="flex min-h-0 flex-1 flex-col">{children}</div>

        {footer && (
          <div className="flex shrink-0 items-center gap-3 border-t border-border px-5 py-4">
            {footer}
          </div>
        )}
      </div>
    </dialog>
  );
}
