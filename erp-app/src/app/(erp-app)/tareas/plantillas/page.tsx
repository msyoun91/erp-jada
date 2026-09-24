import { notFound } from "next/navigation";
import { puedeAdministrar, puedePedir, puedeVerEquipo, puedeVerPlantillas } from "@/modules/tareas/permissions";
import { getAsignables, getContexto, getPlantillas } from "@/modules/tareas/queries";
import { PlantillasView } from "@/modules/tareas/components/PlantillasView";

export default async function PlantillasPage(props: PageProps<"/tareas/plantillas">) {
  if (!(await puedeVerPlantillas())) notFound();
  const { ver } = await props.searchParams;

  const [plantillas, contexto, asignables, admin, pedir, delegador] = await Promise.all([
    getPlantillas(),
    getContexto(),
    getAsignables(),
    puedeAdministrar(),
    puedePedir(),
    puedeVerEquipo(),
  ]);

  return (
    <PlantillasView
      plantillas={plantillas}
      ver={ver === "catalogo" || (ver === "otras" && admin) ? ver : "mias"}
      ctx={{ ...contexto, asignables, admin, pedir, delegador }}
    />
  );
}
