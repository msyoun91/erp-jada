import { notFound } from "next/navigation";
import { puedeVerTareas } from "@/modules/tareas/permissions";
import { getContexto, getMisHilos } from "@/modules/tareas/queries";
import { HilosView } from "@/modules/tareas/components/HilosView";

export default async function HilosPage() {
  if (!(await puedeVerTareas())) notFound();

  const contexto = await getContexto();
  const hilos = await getMisHilos(contexto.yo);

  return <HilosView hilos={hilos} yo={contexto.yo} nombres={contexto.nombres} />;
}
