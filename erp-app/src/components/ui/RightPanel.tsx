"use client";

import { X } from "lucide-react";

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
  return (
    <div className="fixed inset-0 z-50 flex justify-end">
      <div className="absolute inset-0 bg-[rgba(7,11,20,.55)]" onClick={onClose} />

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
    </div>
  );
}
