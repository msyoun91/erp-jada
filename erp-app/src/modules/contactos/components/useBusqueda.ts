"use client";

import { useEffect, useState } from "react";
import { toast } from "sonner";

type Respuesta<T> = { success: true; resultados: T[] } | { success: false; error: string };

// Lo que devuelve el servidor para el texto, 250 ms después de dejar de
// escribir. `resultados` es null con menos de 2 letras o mientras busca.
export function useBusqueda<T>(texto: string, buscar: (texto: string) => Promise<Respuesta<T>>) {
  const [resultado, setResultado] = useState<{ clave: string; items: T[] } | null>(null);
  const clave = texto.trim();
  const buscable = clave.length >= 2;

  useEffect(() => {
    if (!buscable) return;
    let vigente = true;
    const t = setTimeout(async () => {
      const r = await buscar(clave);
      if (!vigente) return;
      if (!r.success) toast.error(r.error);
      else setResultado({ clave, items: r.resultados });
    }, 250);
    return () => {
      vigente = false;
      clearTimeout(t);
    };
  }, [buscable, clave, buscar]);

  return { buscable, resultados: buscable && resultado?.clave === clave ? resultado.items : null };
}
