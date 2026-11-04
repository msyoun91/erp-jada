"use client";

import { useState } from "react";
import { ArrowDown, ArrowUp, ChevronRight, Trash2 } from "lucide-react";
import { toast } from "sonner";
import { ConfirmModal } from "@/components/ui/Modal";
import { OverflowMenu } from "@/components/ui/OverflowMenu";
import { ordenar, sacar } from "../../actions";
import type { OrdenarForm, TablaContenido } from "../../types";

type Ordenable = OrdenarForm["tabla"];

// Una fila del editor: tocarla abre su panel; el menú la mueve entre sus hermanos o la saca. En un menú y no como
// tres íconos sueltos: en mobile ocupaban un tercio del ancho y la fórmula de la fila se partía en cuatro renglones.
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
  const [sacando, setSacando] = useState(false);

  async function mover(delta: number) {
    const ids = [...hermanos];
    [ids[i], ids[i + delta]] = [ids[i + delta], ids[i]];
    const r = await ordenar({ tabla, ids });
    if (!r.success) toast.error(r.error);
  }

  return (
    <li className="flex items-start gap-1 border-b border-border py-2 last:border-b-0">
      <button className="tap-target flex min-w-0 flex-1 items-center gap-2 text-left" onClick={onAbrir}>
        <div className="min-w-0 flex-1">
          <p className="t-body-m font-medium">{titulo}</p>
          {detalle && <p className="t-caption font-mono">{detalle}</p>}
          {children}
        </div>
        <ChevronRight size={16} strokeWidth={1.75} className="shrink-0 text-text-tertiary" />
      </button>
      <OverflowMenu
        items={[
          ...(i > 0
            ? [{ label: "Subir", icon: <ArrowUp size={14} strokeWidth={1.75} />, onClick: () => mover(-1) }]
            : []),
          ...(i >= 0 && i < hermanos.length - 1
            ? [{ label: "Bajar", icon: <ArrowDown size={14} strokeWidth={1.75} />, onClick: () => mover(1) }]
            : []),
          {
            label: "Sacar",
            icon: <Trash2 size={14} strokeWidth={1.75} />,
            onClick: () => setSacando(true),
            destructive: true,
          },
        ]}
      />
      {sacando && <SacarModal tabla={tabla} id={id} que={que} onClose={() => setSacando(false)} />}
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
      {confirmando && <SacarModal tabla={tabla} id={id} que={que} onClose={() => setConfirmando(false)} />}
    </>
  );
}

function SacarModal({
  tabla,
  id,
  que,
  onClose,
}: {
  tabla: TablaContenido;
  id: string;
  que: string;
  onClose: () => void;
}) {
  return (
    <ConfirmModal
      title={`Sacar ${que}`}
      mensaje="Se lleva lo que depende de ello (las variables y materiales de una pieza, las opciones de un material, sus condiciones) y no vuelve: se carga de nuevo."
      confirmLabel="Sacar"
      onClose={onClose}
      onConfirm={async () => {
        const r = await sacar({ tabla, id });
        if (!r.success) toast.error(r.error);
      }}
    />
  );
}
