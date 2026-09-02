import { notFound } from "next/navigation";
import { puedeVerPlantillas } from "@/modules/tareas/permissions";
import { getItemsPorPlantilla, getPlantillas } from "@/modules/tareas/queries";
import { PlantillasView } from "@/modules/tareas/components/PlantillasView";

export default async function TareasPlantillasPage() {
  if (!(await puedeVerPlantillas())) notFound();

  const [plantillas, itemsPorPlantilla] = await Promise.all([
    getPlantillas(),
    getItemsPorPlantilla(),
  ]);

  return <PlantillasView plantillas={plantillas} itemsPorPlantilla={itemsPorPlantilla} />;
}
