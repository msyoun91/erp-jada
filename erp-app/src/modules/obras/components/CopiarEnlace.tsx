"use client";

import { Link2 } from "lucide-react";
import { toast } from "sonner";

// Acceso directo a la ficha. La URL ya funcionaba como enlace profundo —el
// middleware manda a /login con `next` y vuelve— pero no había forma de
// sacarla de la app sin copiarla de la barra del navegador.
export function CopiarEnlace({ ruta }: { ruta: string }) {
  async function copiar() {
    const url = `${window.location.origin}${ruta}`;
    try {
      await navigator.clipboard.writeText(url);
      toast.success("Enlace copiado");
    } catch {
      // El portapapeles pide contexto seguro y permiso. Si no está, mostrar la
      // URL es mejor que un error que no deja hacer nada.
      toast.info(url, { duration: 15000 });
    }
  }

  return (
    <button type="button" className="btn btn-ghost btn-sm" onClick={copiar}>
      <Link2 size={14} />
      Copiar enlace
    </button>
  );
}
