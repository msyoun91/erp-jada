import { notFound } from "next/navigation";
import { puedeVerPlantillas } from "@/modules/tareas/permissions";
import { getPlantillaItems, getPlantillas } from "@/modules/tareas/queries";
import { PlantillasView } from "@/modules/tareas/components/PlantillasView";
import type { TareaPlantillaItem } from "@/modules/tareas/types";

export default async function TareasPlantillasPage() {
  if (!(await puedeVerPlantillas())) notFound();

  const plantillas = await getPlantillas();
  const itemsPorPlantilla: Record<string, TareaPlantillaItem[]> = {};
  await Promise.all(
    plantillas.map(async (p) => {
      itemsPorPlantilla[p.id] = await getPlantillaItems(p.id);
    })
  );

  return <PlantillasView plantillas={plantillas} itemsPorPlantilla={itemsPorPlantilla} />;
}
