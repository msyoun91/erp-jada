import { puedeVerTareas } from "@/modules/tareas/permissions";
import { getContexto, getHilo, getHiloDePaso } from "@/modules/tareas/queries";
import { HiloFicha } from "@/modules/tareas/components/HiloFicha";

// La ficha del hilo en la pestaña de otro paso; su página es `HiloView` (registro.md).
// `resaltado`: el paso desplegado, cuando es la ficha de ese paso.
export async function fichaHilo(id: string, resaltado: string | null = null) {
  if (!(await puedeVerTareas())) return null;
  const [datos, { yo, nombres }] = await Promise.all([getHilo(id), getContexto()]);
  if (!datos) return null;
  return <HiloFicha hilo={datos.hilo} pasos={datos.pasos} sobre={datos.sobre} nombres={nombres} yo={yo} resaltado={resaltado} />;
}

export async function fichaTarea(id: string) {
  if (!(await puedeVerTareas())) return null;
  const hilo = await getHiloDePaso(id);
  return hilo ? fichaHilo(hilo, id) : null;
}
