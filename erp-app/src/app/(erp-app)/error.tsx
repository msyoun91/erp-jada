"use client";

import { WifiOff } from "lucide-react";
import { Vacio } from "@/components/ui/Vacio";

export default function Error({ reset }: { error: Error; reset: () => void }) {
  return (
    <Vacio
      icono={WifiOff}
      titulo="No se pudo cargar esta sección"
      accion={
        <button className="btn btn-secondary" onClick={reset}>
          Reintentar
        </button>
      }
    >
      Puede ser la conexión. Probá de nuevo en un momento.
    </Vacio>
  );
}
