import { notFound } from "next/navigation";
import { puedeVerPlantillas } from "@/modules/tareas/permissions";
import { getPlantillas } from "@/modules/tareas/queries";
import { PlantillasView } from "@/modules/tareas/components/PlantillasView";

export default async function PlantillasPage() {
  if (!(await puedeVerPlantillas())) notFound();

  const plantillas = await getPlantillas();

  return <PlantillasView plantillas={plantillas} />;
}
