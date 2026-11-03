"use client";

import { useState } from "react";
import { ArrowDown, ArrowUp, Trash2 } from "lucide-react";
import { toast } from "sonner";
import { ConfirmModal } from "@/components/ui/Modal";
import { ordenar, sacar } from "../../actions";
import type { OrdenarForm, TablaContenido } from "../../types";

type Ordenable = OrdenarForm["tabla"];

// Una fila del editor: tocarla abre su panel; las flechas la mueven entre sus hermanos.
export function Fila({
  titulo,
  detalle,
  onAbrir,
  tabla,
  id,
  hermanos,
  que,
  children,
}: {
  titulo: string;
  detalle?: string;
  onAbrir: () => void;
  tabla: Ordenable;
  id: string;
  hermanos: string[];
  que: string;
  children?: React.ReactNode;
}) {
  const i = hermanos.indexOf(id);

  async function mover(delta: number) {
    const ids = [...hermanos];
    [ids[i], ids[i + delta]] = [ids[i + delta], ids[i]];
    const r = await ordenar({ tabla, ids });
    if (!r.success) toast.error(r.error);
  }

  return (
    <li className="flex items-start gap-1 border-b border-border py-2 last:border-b-0">
      <button className="tap-target min-w-0 flex-1 text-left" onClick={onAbrir}>
        <p className="t-body-m font-medium">{titulo}</p>
        {detalle && <p className="t-caption font-mono">{detalle}</p>}
        {children}
      </button>
      <button className="icon-btn" aria-label={`Subir ${que}`} disabled={i <= 0} onClick={() => mover(-1)}>
        <ArrowUp size={14} strokeWidth={1.75} />
      </button>
      <button
        className="icon-btn"
        aria-label={`Bajar ${que}`}
        disabled={i < 0 || i >= hermanos.length - 1}
        onClick={() => mover(1)}
      >
        <ArrowDown size={14} strokeWidth={1.75} />
      </button>
      <SacarBoton tabla={tabla} id={id} que={que} />
    </li>
  );
}

// Sacar no se deshace (CA015) y se lleva lo que depende de ello: siempre pregunta.
export function SacarBoton({ tabla, id, que }: { tabla: TablaContenido; id: string; que: string }) {
  const [confirmando, setConfirmando] = useState(false);
  return (
    <>
      <button className="icon-btn text-text-tertiary" aria-label={`Sacar ${que}`} onClick={() => setConfirmando(true)}>
        <Trash2 size={14} strokeWidth={1.75} />
      </button>
      {confirmando && (
        <ConfirmModal
          title={`Sacar ${que}`}
          mensaje="Se lleva lo que depende de ello (las variables y materiales de una pieza, las opciones de un material, sus condiciones) y no vuelve: se carga de nuevo."
          confirmLabel="Sacar"
          onClose={() => setConfirmando(false)}
          onConfirm={async () => {
            const r = await sacar({ tabla, id });
            if (!r.success) toast.error(r.error);
          }}
        />
      )}
    </>
  );
}
