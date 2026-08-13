"use client";

import { useState, useTransition } from "react";
import { Settings2 } from "lucide-react";
import { toggleWidget } from "../actions";
import type { WidgetDefinicion } from "../types";

type Props = {
  widgets: WidgetDefinicion[];
  prefs: Record<string, boolean>;
};

export function ConfigurarWidgets({ widgets, prefs }: Props) {
  const [open, setOpen] = useState(false);
  const [isPending, startTransition] = useTransition();

  function toggle(widgetId: string, visible: boolean) {
    startTransition(() => {
      toggleWidget(widgetId, visible);
    });
  }

  return (
    <div className="relative">
      <button
        type="button"
        className="btn btn-secondary btn-sm"
        onClick={() => setOpen((v) => !v)}
      >
        <Settings2 size={14} strokeWidth={1.75} />
        Configurar
      </button>

      {open && (
        <div className="absolute right-0 z-10 mt-2 w-56 rounded-md border border-border bg-bg-surface p-3 shadow-lg">
          {widgets.map((widget) => (
            <label key={widget.id} className="t-body-m flex items-center gap-2 py-1">
              <input
                type="checkbox"
                defaultChecked={prefs[widget.id] ?? true}
                disabled={isPending}
                onChange={(e) => toggle(widget.id, e.target.checked)}
              />
              {widget.titulo}
            </label>
          ))}
        </div>
      )}
    </div>
  );
}
