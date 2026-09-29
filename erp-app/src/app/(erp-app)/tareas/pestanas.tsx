import { Fragment } from "react";
import { REFERENCIA } from "@/modules/tareas/derivados";
import type { HiloCompleto } from "@/modules/tareas/queries";
import type { Hilo } from "@/modules/tareas/types";
import type { Pestana } from "@/modules/tareas/components/Fichas";
import { ficha, type AccionFicha } from "../fichas";

// Las pestañas de un paso abierto: el registro del hilo primero, después lo que
// menciona su descripción y quien lee puede abrir, sin repetir (registro.md).
// El link de acción (`?vincular=`, `?estado=`) abre su panel en la pestaña del
// registro; la key la vuelve a montar para que lo tome.
export async function pestanasDePaso(
  hilo: Pick<Hilo, "id" | "registro_ente" | "registro_id">,
  sobre: HiloCompleto["sobre"],
  descripcion: string | null,
  enlaces: Record<string, string>,
  accion?: AccionFicha
): Promise<Pestana[]> {
  const { registro_ente, registro_id } = hilo;
  const pestanas: Pestana[] = [];
  const tab = registro_ente && registro_id ? await ficha(registro_ente, registro_id, hilo.id, accion) : null;
  if (tab && sobre)
    pestanas.push({
      ref: `${registro_ente}:${registro_id}`,
      etiqueta: sobre.etiqueta,
      ficha: <Fragment key={`${accion?.vincular}:${accion?.estado}`}>{tab}</Fragment>,
    });
  const refs = [...(descripcion ?? "").matchAll(REFERENCIA)]
    .map(([, ente, rid, nombre]) => ({ ref: `${ente}:${rid}`, ente, rid, nombre }))
    .filter((r, i, todas) => r.ref in enlaces && todas.findIndex((o) => o.ref === r.ref) === i)
    .filter((r) => !pestanas.some((p) => p.ref === r.ref));
  const fichas = await Promise.all(refs.map((r) => ficha(r.ente, r.rid, hilo.id)));
  refs.forEach((r, i) => {
    if (fichas[i]) pestanas.push({ ref: r.ref, etiqueta: r.nombre, ficha: fichas[i] });
  });
  return pestanas;
}
