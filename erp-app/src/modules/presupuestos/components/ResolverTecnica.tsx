"use client";

import { useState } from "react";
import { toast } from "sonner";
import { ConfirmModal } from "@/components/ui/Modal";
import { autorizarPedido } from "../actions";
import { AUTORIZAR_TECNICA, DevolverModal } from "./AntesDePublicar";

// Autorizar o devolver una ventana desde Revisión técnica. Devolver devuelve la versión entera (`presupuestos_pedido_resolver`).
export function ResolverTecnica({ pedidoId, etiqueta }: { pedidoId: string; etiqueta: string }) {
  const [abierto, setAbierto] = useState<"autorizar" | "devolver" | null>(null);
  const cerrar = () => setAbierto(null);

  return (
    <div className="mt-1 flex flex-wrap gap-2">
      <button className="btn btn-primary btn-sm" onClick={() => setAbierto("autorizar")}>
        Autorizar
      </button>
      <button className="btn btn-secondary btn-sm" onClick={() => setAbierto("devolver")}>
        Devolver
      </button>
      {abierto === "autorizar" && (
        <ConfirmModal
          title={`Autorizar ${etiqueta}`}
          mensaje={AUTORIZAR_TECNICA}
          confirmLabel="Autorizar"
          onClose={cerrar}
          onConfirm={async () => {
            const r = await autorizarPedido(pedidoId);
            if (!r.success) toast.error(r.error);
            else toast.success(`${etiqueta}: autorizada`);
          }}
        />
      )}
      {abierto === "devolver" && (
        <DevolverModal id={pedidoId} ejemplo="Ej: con 2600 de ancho la hoja no sale; que la partan en dos" onClose={cerrar} />
      )}
    </div>
  );
}
